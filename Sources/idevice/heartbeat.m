// Jackson Coxson
// heartbeat.c

#include "idevice.h"
#include <arpa/inet.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/_types/_u_int64_t.h>
#include <CoreFoundation/CoreFoundation.h>
#include <limits.h>
#include <signal.h>
#include <setjmp.h>
#include "heartbeat.h"
@import Foundation;

bool isHeartbeat = false;
NSDate* lastHeartbeatDate = nil;

// Signal handling for catching Rust panics
static sigjmp_buf heartbeat_jmp_env;
static volatile sig_atomic_t heartbeat_signal_caught = 0;

static void heartbeat_signal_handler(int signum) {
    heartbeat_signal_caught = signum;
    siglongjmp(heartbeat_jmp_env, signum);
}

// Install signal handler for critical section
static struct sigaction old_sigabrt_action;
static struct sigaction old_sigsegv_action;

static void install_signal_handlers(void) {
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = heartbeat_signal_handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;
    
    sigaction(SIGABRT, &sa, &old_sigabrt_action);
    sigaction(SIGSEGV, &sa, &old_sigsegv_action);
}

static void restore_signal_handlers(void) {
    sigaction(SIGABRT, &old_sigabrt_action, NULL);
    sigaction(SIGSEGV, &old_sigsegv_action, NULL);
}

static NSArray<NSString *> *TunnelIPCandiates(void) {
    NSString *override = [[NSUserDefaults standardUserDefaults] stringForKey:@"TunnelDeviceIP"];
    NSMutableArray<NSString *> *ips = [NSMutableArray array];

    // User override first
    if (override.length > 0) {
        [ips addObject:override];
    }

    // Auto fallback order:
    //  - SideStore LocalDevVPN commonly uses 10.7.0.1 as tunnel peer
    //  - StikDebug legacy commonly uses 10.7.0.2
    [ips addObject:@"10.7.0.1"];
    [ips addObject:@"10.7.0.2"];

    // De-dup while preserving order
    NSMutableOrderedSet *set = [NSMutableOrderedSet orderedSetWithArray:ips];
    return set.array;
}

void startHeartbeat(IdevicePairingFile* pairing_file,
                    IdeviceProviderHandle** provider,
                    bool* isHeartbeat,
                    HeartbeatCompletionHandlerC completion,
                    LogFuncC logger)
{
    // Initialize logger (stderr/stdout from idevice will go to default logger)
    idevice_init_logger(Debug, Disabled, NULL);

    if (*isHeartbeat) {
        if (logger) logger("Heartbeat: already running, skipping");
        return;
    }
    
    // Note: startHeartbeat should only be called from one thread at a time
    // The caller (JITEnableContext) ensures this by checking isHeartbeat flag
    // before calling this function

    NSArray<NSString *> *ips = TunnelIPCandiates();
    
    if (logger) logger("Heartbeat: starting connection attempts to %lu IP(s)", (unsigned long)ips.count);

    IdeviceProviderHandle* newProvider = NULL;
    HeartbeatClientHandle *client = NULL;
    IdeviceFfiError* err = NULL;
    
    BOOL connectionAttempted = NO;
    NSMutableString *allErrors = [NSMutableString string];

    // Try each candidate IP until we can connect heartbeat
    for (NSString *ip in ips) {
        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin_family = AF_INET;
        addr.sin_port = htons(LOCKDOWN_PORT);

        if (inet_pton(AF_INET, ip.UTF8String, &addr.sin_addr) != 1) {
            if (logger) logger("Heartbeat: invalid IP format: %s", ip.UTF8String);
            [allErrors appendFormat:@"Invalid IP: %@; ", ip];
            continue;
        }

        if (logger) logger("Heartbeat: attempting connection to %s:%d", ip.UTF8String, LOCKDOWN_PORT);

        // Clean up from previous iteration ONLY if provider was successfully created
        // This prevents double-free or freeing unallocated memory
        if (newProvider != NULL) {
            if (logger) logger("Heartbeat: cleaning up previous provider before retry");
            idevice_provider_free(newProvider);
            newProvider = NULL;
        }
        
        // Create TCP provider
        err = idevice_tcp_provider_new((struct sockaddr *)&addr,
                                       pairing_file,
                                       "ExampleProvider",
                                       &newProvider);
        if (err != NULL) {
            if (logger) logger("Heartbeat: provider creation failed on %s: [%d] %s",
                               ip.UTF8String, err->code, err->message);
            [allErrors appendFormat:@"%@ provider_new failed [%d]: %s; ",
                ip, err->code, err->message];
            idevice_error_free(err);
            err = NULL;
            // IMPORTANT: Don't free newProvider here as it wasn't successfully allocated
            // The provider_new failure means newProvider is still NULL or invalid
            newProvider = NULL;
            continue;
        }
        
        // Validate provider was created successfully
        if (newProvider == NULL) {
            if (logger) logger("Heartbeat: provider is NULL after creation on %s", ip.UTF8String);
            [allErrors appendFormat:@"%@ provider is NULL; ", ip];
            // No need to free NULL pointer
            continue;
        }

        if (logger) logger("Heartbeat: provider created, attempting heartbeat connection...");
        connectionAttempted = YES;
        
        // Try to connect heartbeat client
        // Note: This call may panic in the Rust layer if TCP connection fails unexpectedly
        // We use signal handlers to catch SIGABRT/SIGSEGV and prevent app crash
        
        heartbeat_signal_caught = 0;
        install_signal_handlers();
        
        int jmp_result = sigsetjmp(heartbeat_jmp_env, 1);
        if (jmp_result == 0) {
            // Normal execution path
            @try {
                client = NULL;
                err = heartbeat_connect(newProvider, &client);
                
                // Restore signal handlers after successful call
                restore_signal_handlers();
                
                if (err != NULL) {
                    if (logger) logger("Heartbeat: connection failed on %s: [%d] %s",
                                       ip.UTF8String, err->code, err->message);
                    [allErrors appendFormat:@"%@ connect failed [%d]: %s; ",
                        ip, err->code, err->message];
                        
                    idevice_provider_free(newProvider);
                    newProvider = NULL;
                    idevice_error_free(err);
                    err = NULL;
                    continue;
                }
                
                // Validate client was created successfully
                if (client == NULL) {
                    if (logger) logger("Heartbeat: client is NULL after connection on %s", ip.UTF8String);
                    [allErrors appendFormat:@"%@ client is NULL; ", ip];
                    
                    idevice_provider_free(newProvider);
                    newProvider = NULL;
                    continue;
                }

                // SUCCESS on this IP
                if (logger) logger("Heartbeat: successfully connected via %s", ip.UTF8String);
                break;
                
            } @catch (NSException *exception) {
                // Catch any Objective-C exceptions that might be thrown
                restore_signal_handlers();
                
                if (logger) logger("Heartbeat: exception during connection to %s: %s",
                                   ip.UTF8String, exception.reason.UTF8String);
                [allErrors appendFormat:@"%@ exception: %@; ", ip, exception.reason];
                
                if (newProvider != NULL) {
                    idevice_provider_free(newProvider);
                    newProvider = NULL;
                }
                continue;
            }
        } else {
            // Signal was caught (Rust panic or segfault)
            restore_signal_handlers();
            
            const char *signame = (jmp_result == SIGABRT) ? "SIGABRT" :
                                  (jmp_result == SIGSEGV) ? "SIGSEGV" : "Unknown";
            if (logger) logger("Heartbeat: caught signal %s during connection to %s (likely Rust panic)",
                               signame, ip.UTF8String);
            [allErrors appendFormat:@"%@ signal %s caught (Rust panic); ", ip, signame];
            
            // Clean up after signal
            if (newProvider != NULL) {
                idevice_provider_free(newProvider);
                newProvider = NULL;
            }
            client = NULL;
            continue;
        }
    }

    // Check if connection succeeded
    if (!newProvider || !client) {
        NSString *errorMsg = [NSString stringWithFormat:
            @"Failed to connect Heartbeat on any IP. Tried: %@. Errors: %@",
            [ips componentsJoinedByString:@", "], allErrors];
        
        if (logger) logger("Heartbeat: %s", errorMsg.UTF8String);
        fprintf(stderr, "%s\n", errorMsg.UTF8String);
        
        idevice_pairing_file_free(pairing_file);
        *isHeartbeat = false;
        
        // Call completion handler with error
        if (completion) {
            if (connectionAttempted) {
                completion(-1, "Connection failed - check VPN/network");
            } else {
                completion(-2, "No valid IPs to connect to");
            }
        }
        return;
    }

    // Mark heartbeat as success and set the default provider
    *isHeartbeat = true;
    *provider = newProvider;
    
    if (logger) logger("Heartbeat: initialization complete, starting keepalive loop");
    completion(0, "Heartbeat Connected");

    // Heartbeat keepalive loop
    u_int64_t current_interval = 15;
    while (1) {
        // Get the new interval
        u_int64_t new_interval = 0;
        err = heartbeat_get_marco(client, current_interval, &new_interval);
        if (err != NULL) {
            if (logger) logger("Heartbeat: get_marco failed: [%d] %s", err->code, err->message);
            fprintf(stderr, "Heartbeat: Failed to get marco: [%d] %s\n", err->code, err->message);
            heartbeat_client_free(client);
            idevice_error_free(err);
            *isHeartbeat = false;
            return;
        }
        current_interval = new_interval + 5;
        
        // Update last heartbeat timestamp
        lastHeartbeatDate = [NSDate date];

        // Reply
        err = heartbeat_send_polo(client);
        if (err != NULL) {
            if (logger) logger("Heartbeat: send_polo failed: [%d] %s", err->code, err->message);
            fprintf(stderr, "Heartbeat: Failed to send polo: [%d] %s\n", err->code, err->message);
            heartbeat_client_free(client);
            idevice_error_free(err);
            *isHeartbeat = false;
            return;
        }
        
        if (logger) logger("Heartbeat: keepalive OK, next in %llus", current_interval);
    }
}
