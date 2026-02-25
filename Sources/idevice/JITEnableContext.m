//
//  JITEnableContext.m
//  StikJIT
//
//  Created by s s on 2025/3/28.
//
#include "idevice.h"
#include <arpa/inet.h>
#include <signal.h>
#include <stdlib.h>

#include "heartbeat.h"
#include "jit.h"
#include "applist.h"
#include "profiles.h"
#include "mount.h"

#include "JITEnableContext.h"
//#import "StikDebug-Swift.h"

JITEnableContext* sharedJITContext = nil;

@implementation JITEnableContext {
    bool heartbeatRunning;
    IdeviceProviderHandle* provider;
    dispatch_queue_t syslogQueue;
    BOOL syslogStreaming;
    SyslogRelayClientHandle *syslogClient;
    SyslogLineHandler syslogLineHandler;
    SyslogErrorHandler syslogErrorHandler;
    dispatch_queue_t processInspectorQueue;
}

+ (instancetype)shared {
    if (!sharedJITContext) {
        sharedJITContext = [[JITEnableContext alloc] init];
    }
    return sharedJITContext;
}

- (instancetype)init {
    NSFileManager* fm = [NSFileManager defaultManager];
    NSURL* docPathUrl = [fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL* logURL = [docPathUrl URLByAppendingPathComponent:@"idevice_log.txt"];
    idevice_init_logger(Info, Debug, (char*)logURL.path.UTF8String);
    syslogQueue = dispatch_queue_create("com.stik.syslogrelay.queue", DISPATCH_QUEUE_SERIAL);
    syslogStreaming = NO;
    syslogClient = NULL;
    dispatch_queue_attr_t qosAttr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0);
    processInspectorQueue = dispatch_queue_create("com.stikdebug.processInspector", qosAttr);
    return self;
}

// MARK: - Tunnel IP auto fallback

- (NSArray<NSString*>*)tunnelIPCandidates {
    NSString *override = [[NSUserDefaults standardUserDefaults] stringForKey:@"TunnelDeviceIP"];
    NSMutableArray<NSString *> *ips = [NSMutableArray array];

    if (override.length > 0) {
        [ips addObject:override];
    }

    // Auto fallback order:
    // - SideStore LocalDevVPN commonly uses 10.7.0.1
    // - StikDebug legacy commonly uses 10.7.0.2
    [ips addObject:@"10.7.0.1"];
    [ips addObject:@"10.7.0.2"];

    NSMutableOrderedSet *set = [NSMutableOrderedSet orderedSetWithArray:ips];
    return set.array;
}

- (IdeviceProviderHandle*)createProviderWithPairingFile:(IdevicePairingFile*)pairingFile
                                                  label:(NSString*)label
                                                  error:(NSError**)error
{
    NSArray<NSString*> *candidates = [self tunnelIPCandidates];

    for (NSString *ip in candidates) {
        struct sockaddr_in addr = {0};
        addr.sin_family = AF_INET;
        addr.sin_port = htons(LOCKDOWN_PORT);

        if (inet_pton(AF_INET, ip.UTF8String, &addr.sin_addr) != 1) {
            NSLog(@"[TunnelIP] invalid ip: %@", ip);
            continue;
        }

        IdeviceProviderHandle *tempProvider = NULL;
        IdeviceFfiError *ffiError = idevice_tcp_provider_new((struct sockaddr *)&addr,
                                                            pairingFile,
                                                            label.UTF8String,
                                                            &tempProvider);
        if (!ffiError) {
            NSLog(@"[TunnelIP] provider '%@' connected via %@", label, ip);
            return tempProvider;
        }

        NSLog(@"[TunnelIP] provider_new failed on %@ (label=%@): [%d] %s",
              ip, label, ffiError->code, ffiError->message);
        idevice_error_free(ffiError);
    }

    if (error) {
        *error = [self errorWithStr:@"Failed to open provider on any TunnelDeviceIP candidate (10.7.0.1/10.7.0.2)."
                               code:-1];
    }
    return NULL;
}

- (NSError*)errorWithStr:(NSString*)str code:(int)code {
    return [NSError errorWithDomain:@"StikJIT"
                               code:code
                           userInfo:@{ NSLocalizedDescriptionKey: str }];
}

- (LogFuncC)createCLogger:(LogFunc)logger {
    return ^(const char* format, ...) {
        va_list args;
        va_start(args, format);
        NSString* fmt = [NSString stringWithCString:format encoding:NSASCIIStringEncoding];
        NSString* message = [[NSString alloc] initWithFormat:fmt arguments:args];
        NSLog(@"%@", message);

        if (logger) {
            logger(message);
        }
        va_end(args);
    };
}

- (IdevicePairingFile*)getPairingFileWithError:(NSError**)error {
    NSFileManager* fm = [NSFileManager defaultManager];
    NSURL* docPathUrl = [fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL* pairingFileURL = [docPathUrl URLByAppendingPathComponent:@"pairingFile.plist"];

    if (![fm fileExistsAtPath:pairingFileURL.path]) {
        NSLog(@"Pairing file not found!");
        *error = [self errorWithStr:@"Pairing file not found!" code:-17];
        return nil;
    }

    IdevicePairingFile* pairingFile = NULL;
    IdeviceFfiError* err = idevice_pairing_file_read(pairingFileURL.fileSystemRepresentation, &pairingFile);
    if (err) {
        *error = [self errorWithStr:@"Failed to read pairing file!" code:err->code];
        return nil;
    }
    return pairingFile;
}

- (void)startHeartbeatWithCompletionHandler:(HeartbeatCompletionHandler)completionHandler
                                     logger:(LogFunc)logger
{
    NSError* err = nil;
    IdevicePairingFile* pairingFile = [self getPairingFileWithError:&err];
    if (err) {
        // silently swallow “pairing file not found” (-17)
        if (err.code == -17) {
            return;
        }
        // for all other errors, log and forward
        if (logger) {
            logger(err.localizedDescription);
        }
        completionHandler(err.code, err.localizedDescription);
        return;
    }

    if(heartbeatRunning) {
        return;
    }
    startHeartbeat(
                   pairingFile,
                   &provider,
                   &heartbeatRunning,
                   ^(int result, const char *message) {
                       completionHandler(result,
                                         [NSString stringWithCString:message
                                                            encoding:NSASCIIStringEncoding]);
                   },
                   [self createCLogger:logger]
                   );
}

- (void)ensureHeartbeat {
    // wait a bit until heartbeat finish. wait at most 10s
    int deadline = 50;
    while((!lastHeartbeatDate || [[NSDate now] timeIntervalSinceDate:lastHeartbeatDate] > 15) && deadline) {
        --deadline;
        usleep(200);
    }
}

- (BOOL)afcPushFile:(NSString *)sourcePath toPath:(NSString *)destPath error:(NSError **)error {
    NSLog(@"[afcPushFile] Starting file push: %@ -> %@", sourcePath, destPath);
    
    // Validate provider
    if (!provider) {
        NSLog(@"[afcPushFile] ERROR: Provider not initialized!");
        *error = [self errorWithStr:@"Provider not initialized!" code:-1];
        return NO;
    }
    
    // Validate source file exists
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:sourcePath]) {
        NSLog(@"[afcPushFile] ERROR: Source file does not exist: %@", sourcePath);
        *error = [self errorWithStr:[NSString stringWithFormat:@"Source file does not exist: %@", sourcePath] code:-2];
        return NO;
    }
    
    // Check source file is readable
    if (![fileManager isReadableFileAtPath:sourcePath]) {
        NSLog(@"[afcPushFile] ERROR: Source file is not readable: %@", sourcePath);
        *error = [self errorWithStr:[NSString stringWithFormat:@"Source file is not readable: %@", sourcePath] code:-3];
        return NO;
    }
    
    // Load file data before connecting to device
    NSError *readError = nil;
    NSData* fileData = [NSData dataWithContentsOfFile:sourcePath options:0 error:&readError];
    if (!fileData || readError) {
        NSLog(@"[afcPushFile] ERROR: Failed to read source file: %@", readError.localizedDescription);
        *error = [self errorWithStr:[NSString stringWithFormat:@"Failed to read source file: %@", readError.localizedDescription] code:-4];
        return NO;
    }
    
    NSLog(@"[afcPushFile] Source file loaded: %lu bytes", (unsigned long)fileData.length);
    
    // Connect to AFC client
    struct AfcClientHandle *client = NULL;
    IdeviceFfiError* err = afc_client_connect(provider, &client);
    if (err) {
        NSLog(@"[afcPushFile] ERROR: Failed to connect AFC client - code:%d, msg:%s", err->code, err->message);
        *error = [self errorWithStr:[NSString stringWithFormat:@"Failed to connect to device AFC service (code:%d)", err->code] code:err->code];
        idevice_error_free(err);
        return NO;
    }
    
    NSLog(@"[afcPushFile] AFC client connected successfully");
    
    // Extract directory path from destination
    NSString *destDir = [destPath stringByDeletingLastPathComponent];
    if (destDir && destDir.length > 0 && ![destDir isEqualToString:@"/"]) {
        NSLog(@"[afcPushFile] Ensuring destination directory exists: %@", destDir);
        
        // Try to create directory
        err = afc_make_directory(client, destDir.fileSystemRepresentation);
        if (err) {
            // Directory creation failed - check if it's because it already exists
            // Error code -17 (EEXIST) means directory already exists, which is OK
            if (err->code == -17) {
                NSLog(@"[afcPushFile] Directory already exists: %@", destDir);
            } else {
                // Other errors might indicate permission issues or other problems
                NSLog(@"[afcPushFile] WARNING: Directory creation failed with code:%d, msg:%s", err->code, err->message);
                // Continue anyway - the file open will fail with a clear error if directory is truly inaccessible
            }
            idevice_error_free(err);
        } else {
            NSLog(@"[afcPushFile] Directory created successfully: %@", destDir);
        }
    }
    
    // Open destination file for writing
    struct AfcFileHandle *handle = NULL;
    err = afc_file_open(client, destPath.fileSystemRepresentation, AfcWrOnly, &handle);
    if (err) {
        NSLog(@"[afcPushFile] ERROR: Failed to open destination file - code:%d, msg:%s", err->code, err->message);
        
        // Provide detailed error message based on error code
        // Note: These are common POSIX-style error codes. AFC service typically returns
        // standard errno values, but the exact codes may vary. Logging the actual error
        // code helps diagnose any discrepancies.
        NSString *detailedMsg;
        switch (err->code) {
            case -2:  // ENOENT - No such file or directory
                detailedMsg = [NSString stringWithFormat:@"Destination path does not exist or is invalid: %@", destPath];
                break;
            case -13: // EACCES - Permission denied
                detailedMsg = @"Permission denied. The app does not have access to write to this location.";
                break;
            case -28: // ENOSPC - No space left on device
                detailedMsg = @"Insufficient storage space on device.";
                break;
            case -17: // EEXIST - File exists
                detailedMsg = [NSString stringWithFormat:@"File already exists and cannot be overwritten: %@", destPath];
                break;
            default:
                detailedMsg = [NSString stringWithFormat:@"Failed to open destination file on device (error code:%d): %@", err->code, destPath];
                break;
        }
        
        *error = [self errorWithStr:detailedMsg code:err->code];
        idevice_error_free(err);
        afc_client_free(client);
        return NO;
    }
    
    NSLog(@"[afcPushFile] Destination file opened for writing");
    
    // Write file data in chunks to prevent timeout on large files
    // Error code -60 (ETIMEDOUT) can occur when writing large files in one operation
    const size_t CHUNK_SIZE = 256 * 1024; // 256KB chunks
    size_t totalWritten = 0;
    const uint8_t *dataBytes = (const uint8_t *)fileData.bytes;
    size_t totalLength = fileData.length;
    
    NSLog(@"[afcPushFile] Writing %lu bytes in chunks of %zu bytes", (unsigned long)totalLength, CHUNK_SIZE);
    
    while (totalWritten < totalLength) {
        size_t chunkSize = MIN(CHUNK_SIZE, totalLength - totalWritten);
        
        err = afc_file_write(handle, dataBytes + totalWritten, chunkSize);
        if (err) {
            NSLog(@"[afcPushFile] ERROR: Failed to write file data chunk at offset %zu - code:%d, msg:%s",
                  totalWritten, err->code, err->message);
            
            // Provide detailed error message based on error code
            NSString *errorMsg;
            switch (err->code) {
                case -60: // ETIMEDOUT
                    errorMsg = [NSString stringWithFormat:@"Write operation timed out at %zu/%lu bytes. The file may be too large or connection is too slow.",
                               totalWritten, (unsigned long)totalLength];
                    break;
                case -28: // ENOSPC
                    errorMsg = @"Insufficient storage space on device.";
                    break;
                default:
                    errorMsg = [NSString stringWithFormat:@"Failed to write file data (code:%d) at offset %zu/%lu bytes",
                               err->code, totalWritten, (unsigned long)totalLength];
                    break;
            }
            
            *error = [self errorWithStr:errorMsg code:err->code];
            idevice_error_free(err);
            afc_file_close(handle);
            afc_client_free(client);
            return NO;
        }
        
        totalWritten += chunkSize;
        
        // Log progress for large files
        if (totalLength > 1024 * 1024) { // Log progress for files > 1MB
            NSLog(@"[afcPushFile] Progress: %zu/%lu bytes (%.1f%%)",
                  totalWritten, (unsigned long)totalLength,
                  (totalWritten * 100.0) / totalLength);
        }
    }
    
    NSLog(@"[afcPushFile] File data written successfully: %lu bytes", (unsigned long)fileData.length);
    
    // Close file handle
    err = afc_file_close(handle);
    if (err) {
        NSLog(@"[afcPushFile] WARNING: Failed to close file handle - code:%d, msg:%s", err->code, err->message);
        idevice_error_free(err);
        // Continue anyway as data is written
    }
    
    // Clean up AFC client
    afc_client_free(client);
    
    NSLog(@"[afcPushFile] File push completed successfully");
    return YES;
}

- (BOOL)debugAppWithBundleID:(NSString*)bundleID logger:(LogFunc)logger jsCallback:(DebugAppCallback)jsCallback {
    if (!provider) {
        if (logger) {
            logger(@"Provider not initialized!");
        }
        NSLog(@"Provider not initialized!");
        return NO;
    }

    [self ensureHeartbeat];

    return debug_app(provider,
                     [bundleID UTF8String],
                     [self createCLogger:logger], jsCallback) == 0;
}

- (BOOL)debugAppWithPID:(int)pid logger:(LogFunc)logger jsCallback:(DebugAppCallback)jsCallback {
    if (!provider) {
        if (logger) {
            logger(@"Provider not initialized!");
        }
        NSLog(@"Provider not initialized!");
        return NO;
    }

    [self ensureHeartbeat];

    return debug_app_pid(provider,
                         pid,
                         [self createCLogger:logger], jsCallback) == 0;
}

- (NSDictionary<NSString*, NSString*>*)getAppListWithError:(NSError**)error {
    if (!provider) {
        NSLog(@"Provider not initialized!");
        *error = [self errorWithStr:@"Provider not initialized!" code:-1];
        return nil;
    }

    NSString* errorStr = nil;
    NSDictionary<NSString*, NSString*>* apps = list_installed_apps(provider, &errorStr);
    if (errorStr) {
        *error = [self errorWithStr:errorStr code:-17];
        return nil;
    }
    return apps;
}

- (NSDictionary<NSString*, NSString*>*)getAllAppsWithError:(NSError**)error {
    if (!provider) {
        NSLog(@"Provider not initialized!");
        *error = [self errorWithStr:@"Provider not initialized!" code:-1];
        return nil;
    }

    NSString* errorStr = nil;
    NSDictionary<NSString*, NSString*>* apps = list_all_apps(provider, &errorStr);
    if (errorStr) {
        *error = [self errorWithStr:errorStr code:-17];
        return nil;
    }
    return apps;
}

- (NSDictionary<NSString*, NSString*>*)getHiddenSystemAppsWithError:(NSError**)error {
    if (!provider) {
        NSLog(@"Provider not initialized!");
        *error = [self errorWithStr:@"Provider not initialized!" code:-1];
        return nil;
    }

    NSString* errorStr = nil;
    NSDictionary<NSString*, NSString*>* apps = list_hidden_system_apps(provider, &errorStr);
    if (errorStr) {
        *error = [self errorWithStr:errorStr code:-17];
        return nil;
    }
    return apps;
}

- (NSDictionary<NSString*, id>*)getAllAppsInfoWithError:(NSError**)error {
    if (!provider) {
        NSLog(@"Provider not initialized!");
        *error = [self errorWithStr:@"Provider not initialized!" code:-1];
        return nil;
    }

    NSString* errorStr = nil;
    NSDictionary<NSString*, id>* apps = getAllAppsInfo(provider, &errorStr);
    if (errorStr) {
        *error = [self errorWithStr:errorStr code:-17];
        return nil;
    }
    return apps;
}

- (UIImage*)getAppIconWithBundleId:(NSString*)bundleId error:(NSError**)error {
    if (!provider) {
        NSLog(@"Provider not initialized!");
        *error = [self errorWithStr:@"Provider not initialized!" code:-1];
        return nil;
    }

    NSString* errorStr = nil;
    UIImage* icon = getAppIcon(provider, bundleId, &errorStr);
    if (errorStr) {
        *error = [self errorWithStr:errorStr code:-17];
        return nil;
    }
    return icon;
}

- (BOOL)launchAppWithoutDebug:(NSString*)bundleID logger:(LogFunc)logger {
    if (!provider) {
        if (logger) {
            logger(@"Provider not initialized!");
        }
        NSLog(@"Provider not initialized!");
        return NO;
    }

    [self ensureHeartbeat];

    int result = launch_app_via_proxy(provider,
                                      [bundleID UTF8String],
                                      [self createCLogger:logger]);
    return result == 0;
}

- (void)startSyslogRelayWithHandler:(SyslogLineHandler)lineHandler
                             onError:(SyslogErrorHandler)errorHandler
{
    if (!provider) {
        if (errorHandler) {
            errorHandler([self errorWithStr:@"Provider not initialized!" code:-1]);
        }
        return;
    }
    if (!lineHandler || syslogStreaming) {
        return;
    }

    syslogStreaming = YES;
    syslogLineHandler = [lineHandler copy];
    syslogErrorHandler = [errorHandler copy];

    __weak typeof(self) weakSelf = self;
    dispatch_async(syslogQueue, ^{
        __strong typeof(self) strongSelf = weakSelf;
        if (!strongSelf) { return; }

        [strongSelf ensureHeartbeat];

        SyslogRelayClientHandle *client = NULL;
        IdeviceFfiError *err = syslog_relay_connect_tcp(strongSelf->provider, &client);
        if (err != NULL) {
            NSString *message = err->message ? [NSString stringWithCString:err->message encoding:NSASCIIStringEncoding] : @"Failed to connect to syslog relay";
            NSError *nsError = [strongSelf errorWithStr:message code:err->code];
            idevice_error_free(err);
            [strongSelf handleSyslogFailure:nsError];
            return;
        }

        strongSelf->syslogClient = client;

        while (strongSelf && strongSelf->syslogStreaming) {
            char *message = NULL;
            IdeviceFfiError *nextErr = syslog_relay_next(client, &message);
            if (nextErr != NULL) {
                NSString *errMsg = nextErr->message ? [NSString stringWithCString:nextErr->message encoding:NSASCIIStringEncoding] : @"Syslog relay read failed";
                NSError *nsError = [strongSelf errorWithStr:errMsg code:nextErr->code];
                idevice_error_free(nextErr);
                if (message) { idevice_string_free(message); }
                [strongSelf handleSyslogFailure:nsError];
                client = NULL;
                break;
            }

            if (!message) {
                continue;
            }

            NSString *line = [NSString stringWithCString:message encoding:NSUTF8StringEncoding];
            idevice_string_free(message);
            if (!line || !strongSelf->syslogLineHandler) {
                continue;
            }

            SyslogLineHandler handlerCopy = strongSelf->syslogLineHandler;
            if (handlerCopy) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    handlerCopy(line);
                });
            }
        }

        if (client) {
            syslog_relay_client_free(client);
        }

        strongSelf->syslogClient = NULL;
        strongSelf->syslogStreaming = NO;
        strongSelf->syslogLineHandler = nil;
        strongSelf->syslogErrorHandler = nil;
    });
}

- (void)stopSyslogRelay {
    if (!syslogStreaming) {
        return;
    }

    syslogStreaming = NO;
    syslogLineHandler = nil;
    syslogErrorHandler = nil;

    dispatch_async(syslogQueue, ^{
        if (self->syslogClient) {
            syslog_relay_client_free(self->syslogClient);
            self->syslogClient = NULL;
        }
    });
}

- (void)handleSyslogFailure:(NSError *)error {
    syslogStreaming = NO;
    if (syslogClient) {
        syslog_relay_client_free(syslogClient);
        syslogClient = NULL;
    }
    SyslogErrorHandler errorCopy = syslogErrorHandler;
    syslogLineHandler = nil;
    syslogErrorHandler = nil;

    if (errorCopy) {
        dispatch_async(dispatch_get_main_queue(), ^{
            errorCopy(error);
        });
    }
}

- (NSArray<NSData*>*)fetchAllProfiles:(NSError **)error {
    if (!provider) {
        NSLog(@"Provider not initialized!");
        *error = [self errorWithStr:@"Provider not initialized!" code:-1];
        return nil;
    }
    return fetchAppProfiles(provider, error);
}

- (BOOL)removeProfileWithUUID:(NSString*)uuid error:(NSError **)error {
    if (!provider) {
        NSLog(@"Provider not initialized!");
        *error = [self errorWithStr:@"Provider not initialized!" code:-1];
        return nil;
    }
    return removeProfile(provider, uuid, error);
}

- (BOOL)addProfile:(NSData*)profile error:(NSError **)error {
    if (!provider) {
        NSLog(@"Provider not initialized!");
        *error = [self errorWithStr:@"Provider not initialized!" code:-1];
        return nil;
    }
    return addProfile(provider, profile, error);
}

- (void)dealloc {
    [self stopSyslogRelay];
    if (provider) {
        idevice_provider_free(provider);
    }
}

// MARK: - Process list / kill with auto-fallback provider

- (NSArray<NSDictionary*>*)fetchProcessesViaAppServiceWithError:(NSError **)error {
    NSURL *documents = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *pairingURL = [documents URLByAppendingPathComponent:@"pairingFile.plist"];
    IdevicePairingFile *pairingFile = NULL;
    IdeviceProviderHandle *tempProvider = NULL;
    IdeviceProviderHandle *providerToUse = provider;
    CoreDeviceProxyHandle *coreProxy = NULL;
    AdapterHandle *adapter = NULL;
    AdapterStreamHandle *stream = NULL;
    RsdHandshakeHandle *handshake = NULL;
    AppServiceHandle *appService = NULL;
    ProcessTokenC *processes = NULL;
    uintptr_t count = 0;
    NSMutableArray *result = nil;
    IdeviceFfiError *ffiError = NULL;

    do {
        if (!providerToUse) {
            ffiError = idevice_pairing_file_read(pairingURL.path.UTF8String, &pairingFile);
            if (ffiError) {
                if (error) {
                    *error = [self errorWithStr:@"Unable to read pairing file" code:ffiError->code];
                }
                idevice_error_free(ffiError);
                ffiError = NULL;
                break;
            }

            NSError *provErr = nil;
            tempProvider = [self createProviderWithPairingFile:pairingFile label:@"ProcessInspector" error:&provErr];
            if (!tempProvider) {
                if (error) *error = provErr;
                break;
            }
            providerToUse = tempProvider;
        }

        ffiError = core_device_proxy_connect(providerToUse, &coreProxy);
        if (ffiError) {
            if (error) {
                *error = [self errorWithStr:[NSString stringWithUTF8String:ffiError->message ?: "Failed to connect CoreDeviceProxy"]
                                       code:ffiError->code];
            }
            idevice_error_free(ffiError);
            ffiError = NULL;
            break;
        }

        uint16_t rsdPort = 0;
        ffiError = core_device_proxy_get_server_rsd_port(coreProxy, &rsdPort);
        if (ffiError) {
            if (error) {
                *error = [self errorWithStr:[NSString stringWithUTF8String:ffiError->message ?: "Unable to resolve RSD port"]
                                       code:ffiError->code];
            }
            idevice_error_free(ffiError);
            ffiError = NULL;
            break;
        }

        ffiError = core_device_proxy_create_tcp_adapter(coreProxy, &adapter);
        if (ffiError) {
            if (error) {
                *error = [self errorWithStr:[NSString stringWithUTF8String:ffiError->message ?: "Failed to create adapter"]
                                       code:ffiError->code];
            }
            idevice_error_free(ffiError);
            ffiError = NULL;
            break;
        }

        coreProxy = NULL;
        ffiError = adapter_connect(adapter, rsdPort, (ReadWriteOpaque **)&stream);
        if (ffiError) {
            if (error) {
                *error = [self errorWithStr:[NSString stringWithUTF8String:ffiError->message ?: "Adapter connect failed"]
                                       code:ffiError->code];
            }
            idevice_error_free(ffiError);
            ffiError = NULL;
            break;
        }

        ffiError = rsd_handshake_new((ReadWriteOpaque *)stream, &handshake);
        if (ffiError) {
            if (error) {
                *error = [self errorWithStr:[NSString stringWithUTF8String:ffiError->message ?: "RSD handshake failed"]
                                       code:ffiError->code];
            }
            idevice_error_free(ffiError);
            ffiError = NULL;
            break;
        }

        stream = NULL;
        ffiError = app_service_connect_rsd(adapter, handshake, &appService);
        if (ffiError) {
            if (error) {
                *error = [self errorWithStr:[NSString stringWithUTF8String:ffiError->message ?: "Unable to open AppService"]
                                       code:ffiError->code];
            }
            idevice_error_free(ffiError);
            ffiError = NULL;
            break;
        }

        ffiError = app_service_list_processes(appService, &processes, &count);
        if (ffiError) {
            if (error) {
                *error = [self errorWithStr:[NSString stringWithUTF8String:ffiError->message ?: "Failed to list processes"]
                                       code:ffiError->code];
            }
            idevice_error_free(ffiError);
            ffiError = NULL;
            break;
        }

        result = [NSMutableArray arrayWithCapacity:count];
        for (uintptr_t idx = 0; idx < count; idx++) {
            ProcessTokenC proc = processes[idx];
            NSMutableDictionary *entry = [NSMutableDictionary dictionary];
            entry[@"pid"] = @(proc.pid);
            if (proc.executable_url) {
                entry[@"path"] = [NSString stringWithUTF8String:proc.executable_url];
            }
            [result addObject:entry];
        }
    } while (0);

    if (processes && count > 0) {
        app_service_free_process_list(processes, count);
    }
    if (appService) {
        app_service_free(appService);
    }
    if (handshake) {
        rsd_handshake_free(handshake);
    }
    if (stream) {
        adapter_stream_close(stream);
    }
    if (adapter) {
        adapter_free(adapter);
    }
    if (coreProxy) {
        core_device_proxy_free(coreProxy);
    }
    if (tempProvider) {
        idevice_provider_free(tempProvider);
    }
    if (pairingFile) {
        idevice_pairing_file_free(pairingFile);
    }
    return result;
}

- (NSArray<NSDictionary*>*)_fetchProcessListLocked:(NSError**)error {
    if (provider) {
        [self ensureHeartbeat];
    }
    return [self fetchProcessesViaAppServiceWithError:error];
}

- (NSArray<NSDictionary*>*)fetchProcessListWithError:(NSError**)error {
    __block NSArray *result = nil;
    __block NSError *localError = nil;
    dispatch_sync(processInspectorQueue, ^{
        result = [self _fetchProcessListLocked:&localError];
    });
    if (error && localError) {
        *error = localError;
    }
    return result;
}

- (BOOL)killProcessWithPID:(int)pid signal:(int)signal error:(NSError **)error {
    NSURL *documents = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *pairingURL = [documents URLByAppendingPathComponent:@"pairingFile.plist"];
    IdevicePairingFile *pairingFile = NULL;
    IdeviceProviderHandle *tempProvider = NULL;
    IdeviceProviderHandle *providerToUse = provider;
    CoreDeviceProxyHandle *coreProxy = NULL;
    AdapterHandle *adapter = NULL;
    AdapterStreamHandle *stream = NULL;
    RsdHandshakeHandle *handshake = NULL;
    AppServiceHandle *appService = NULL;
    SignalResponseC *signalResponse = NULL;
    IdeviceFfiError *ffiError = NULL;
    BOOL success = NO;

    do {
        if (!providerToUse) {
            ffiError = idevice_pairing_file_read(pairingURL.path.UTF8String, &pairingFile);
            if (ffiError) {
                if (error) {
                    *error = [self errorWithStr:@"Unable to read pairing file" code:ffiError->code];
                }
                idevice_error_free(ffiError);
                ffiError = NULL;
                break;
            }

            NSError *provErr = nil;
            tempProvider = [self createProviderWithPairingFile:pairingFile label:@"ProcessInspectorKill" error:&provErr];
            if (!tempProvider) {
                if (error) *error = provErr;
                break;
            }
            providerToUse = tempProvider;
        } else {
            [self ensureHeartbeat];
        }

        ffiError = core_device_proxy_connect(providerToUse, &coreProxy);
        if (ffiError) {
            if (error) {
                *error = [self errorWithStr:[NSString stringWithUTF8String:ffiError->message ?: "Failed to connect CoreDeviceProxy"]
                                       code:ffiError->code];
            }
            idevice_error_free(ffiError);
            ffiError = NULL;
            break;
        }

        uint16_t rsdPort = 0;
        ffiError = core_device_proxy_get_server_rsd_port(coreProxy, &rsdPort);
        if (ffiError) {
            if (error) {
                *error = [self errorWithStr:[NSString stringWithUTF8String:ffiError->message ?: "Unable to resolve RSD port"]
                                       code:ffiError->code];
            }
            idevice_error_free(ffiError);
            ffiError = NULL;
            break;
        }

        ffiError = core_device_proxy_create_tcp_adapter(coreProxy, &adapter);
        if (ffiError) {
            if (error) {
                *error = [self errorWithStr:[NSString stringWithUTF8String:ffiError->message ?: "Failed to create adapter"]
                                       code:ffiError->code];
            }
            idevice_error_free(ffiError);
            ffiError = NULL;
            break;
        }

        coreProxy = NULL;
        ffiError = adapter_connect(adapter, rsdPort, (ReadWriteOpaque **)&stream);
        if (ffiError) {
            if (error) {
                *error = [self errorWithStr:[NSString stringWithUTF8String:ffiError->message ?: "Adapter connect failed"]
                                       code:ffiError->code];
            }
            idevice_error_free(ffiError);
            ffiError = NULL;
            break;
        }

        ffiError = rsd_handshake_new((ReadWriteOpaque *)stream, &handshake);
        if (ffiError) {
            if (error) {
                *error = [self errorWithStr:[NSString stringWithUTF8String:ffiError->message ?: "RSD handshake failed"]
                                       code:ffiError->code];
            }
            idevice_error_free(ffiError);
            ffiError = NULL;
            break;
        }

        stream = NULL;
        ffiError = app_service_connect_rsd(adapter, handshake, &appService);
        if (ffiError) {
            if (error) {
                *error = [self errorWithStr:[NSString stringWithUTF8String:ffiError->message ?: "Unable to open AppService"]
                                       code:ffiError->code];
            }
            idevice_error_free(ffiError);
            ffiError = NULL;
            break;
        }

        ffiError = app_service_send_signal(appService, (uint32_t)pid, signal, &signalResponse);
        if (ffiError) {
            if (error) {
                *error = [self errorWithStr:[NSString stringWithUTF8String:ffiError->message ?: "Failed to kill process"]
                                       code:ffiError->code];
            }
            idevice_error_free(ffiError);
            ffiError = NULL;
            break;
        }
        success = YES;
    } while (0);

    if (signalResponse) {
        app_service_free_signal_response(signalResponse);
    }
    if (appService) {
        app_service_free(appService);
    }
    if (handshake) {
        rsd_handshake_free(handshake);
    }
    if (stream) {
        adapter_stream_close(stream);
    }
    if (adapter) {
        adapter_free(adapter);
    }
    if (coreProxy) {
        core_device_proxy_free(coreProxy);
    }
    if (tempProvider) {
        idevice_provider_free(tempProvider);
    }
    if (pairingFile) {
        idevice_pairing_file_free(pairingFile);
    }
    return success;
}

// MARK: - Developer Disk Image Mounting

// Constants for DDI mounting
static NSString * const kDDIImageTypeKey = @"Developer";
static NSString * const kDDIPathiOS17Plus = @"/System/Developer/Library";
static NSString * const kDDIPathLegacy = @"/Developer/Library";

- (BOOL)isDeveloperDiskImageMounted {
    // Check both paths for compatibility
    // Note: These directories are only created by iOS when DDI is actually mounted.
    // They don't exist by default, so directory existence is a reliable indicator.
    BOOL ios17PathExists = [[NSFileManager defaultManager] fileExistsAtPath:kDDIPathiOS17Plus];
    BOOL legacyPathExists = [[NSFileManager defaultManager] fileExistsAtPath:kDDIPathLegacy];
    return ios17PathExists || legacyPathExists;
}

- (BOOL)mountDeveloperDiskImageWithProgress:(void (^)(NSString *status))progressHandler error:(NSError **)error {
    if (!provider) {
        if (error) {
            *error = [self errorWithStr:@"Provider not initialized. Start heartbeat first." code:-1];
        }
        return NO;
    }
    
    // Check if already mounted
    if ([self isDeveloperDiskImageMounted]) {
        if (progressHandler) {
            progressHandler(@"DDI already mounted");
        }
        return YES;
    }
    
    if (progressHandler) {
        progressHandler(@"Connecting to ImageMounter service...");
    }
    
    // Connect to ImageMounter service
    ImageMounterHandle *imageMounter = NULL;
    IdeviceFfiError *ffiError = image_mounter_connect(provider, &imageMounter);
    if (ffiError) {
        if (error) {
            NSString *msg = ffiError->message ? [NSString stringWithUTF8String:ffiError->message] : @"Failed to connect to ImageMounter";
            *error = [self errorWithStr:msg code:ffiError->code];
        }
        idevice_error_free(ffiError);
        return NO;
    }
    
    BOOL success = NO;
    
    @try {
        if (progressHandler) {
            progressHandler(@"Querying developer mode status...");
        }
        
        // Query developer mode status
        bool devModeEnabled = false;
        ffiError = image_mounter_query_developer_mode_status(imageMounter, &devModeEnabled);
        if (ffiError) {
            if (error) {
                NSString *msg = ffiError->message ? [NSString stringWithUTF8String:ffiError->message] : @"Failed to query developer mode status";
                *error = [self errorWithStr:msg code:ffiError->code];
            }
            idevice_error_free(ffiError);
            return NO;
        }
        
        if (!devModeEnabled) {
            if (progressHandler) {
                progressHandler(@"Developer mode is not enabled on device");
            }
            if (error) {
                *error = [self errorWithStr:@"Developer mode must be enabled on the device. Go to Settings > Privacy & Security > Developer Mode and enable it." code:-2];
            }
            return NO;
        }
        
        if (progressHandler) {
            progressHandler(@"Developer mode enabled, attempting to mount DDI...");
        }
        
        // Try to mount developer disk image
        // Note: This requires the device to be in developer mode (iOS 16+)
        // For older devices, a personalized DDI may be required
        //
        // NULL image and signature parameters: Modern iOS with Developer Mode enabled (iOS 16+)
        // does not require actual DDI image files or signatures. The device uses built-in
        // developer disk images when Developer Mode is enabled.
        // For older iOS versions that require personalized DDI, non-NULL image and signature
        // data would be needed.
        ffiError = image_mounter_mount_developer(imageMounter, NULL, 0, NULL, 0);
        if (ffiError) {
            // If mounting fails, it might already be mounted or require personalization
            NSString *msg = ffiError->message ? [NSString stringWithUTF8String:ffiError->message] : @"Failed to mount developer disk image";
            NSLog(@"[DDI Mount] Warning: %@", msg);
            
            // Check if it's actually mounted now (sometimes the error is misleading)
            if ([self isDeveloperDiskImageMounted]) {
                if (progressHandler) {
                    progressHandler(@"DDI mounted successfully");
                }
                success = YES;
            } else {
                if (error) {
                    *error = [self errorWithStr:[NSString stringWithFormat:@"%@. The device may require a personalized DDI or additional setup.", msg] code:ffiError->code];
                }
                idevice_error_free(ffiError);
                return NO;
            }
        } else {
            if (progressHandler) {
                progressHandler(@"DDI mounted successfully");
            }
            success = YES;
        }
        
        // Verify mount
        if (![self isDeveloperDiskImageMounted]) {
            if (error) {
                *error = [self errorWithStr:@"DDI mount command succeeded but DDI path not found. Device may need restart." code:-3];
            }
            return NO;
        }
        
        return success;
        
    } @finally {
        if (imageMounter) {
            image_mounter_free(imageMounter);
        }
    }
}

// MARK: - Personalized DDI Mounting (like StikDebug)

- (NSUInteger)getMountedDeviceCount:(NSError**)error {
    if (!provider) {
        if (error) {
            *error = [self errorWithStr:@"Provider not initialized. Start heartbeat first." code:-1];
        }
        return 0;
    }
    [self ensureHeartbeat];
    return getMountedDeviceCount(provider, error);
}

- (NSInteger)mountPersonalDDIWithImagePath:(NSString*)imagePath trustcachePath:(NSString*)trustcachePath manifestPath:(NSString*)manifestPath error:(NSError**)error {
    if (!provider) {
        if (error) {
            *error = [self errorWithStr:@"Provider not initialized. Start heartbeat first." code:-1];
        }
        return -1;
    }
    [self ensureHeartbeat];
    IdevicePairingFile* pairing = [self getPairingFileWithError:error];
    if (!pairing) {
        return -1;
    }
    return mountPersonalDDI(provider, pairing, imagePath, trustcachePath, manifestPath, error);
}

@end
