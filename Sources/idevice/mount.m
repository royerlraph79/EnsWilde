//
//  mount.m
//  EnsWilde
//
//  DDI mounting support (adapted from StikDebug)
//
#include "mount.h"
#import "JITEnableContext.h"
@import Foundation;

NSError* makeError(int code, NSString* msg);
size_t getMountedDeviceCount(IdeviceProviderHandle* provider, NSError** error) {
    ImageMounterHandle* client = 0;
    IdeviceFfiError* err = image_mounter_connect(provider, &client);
    if (err) {
        *error = makeError(err->code, @(err->message));
        idevice_error_free(err);
        return 0;
    }
    plist_t* devices;
    size_t deviceLength = 0;
    err = image_mounter_copy_devices(client, &devices, &deviceLength);
    if (err) {
        *error = makeError(err->code, @(err->message));
        idevice_error_free(err);
        image_mounter_free(client);
        return 0;
    }
    for(size_t i = 0;i < deviceLength; ++i) {
        plist_free(devices[i]);
    }
    idevice_data_free((uint8_t *)devices, deviceLength*sizeof(plist_t));
    image_mounter_free(client);
    return deviceLength;
}


int mountPersonalDDI(IdeviceProviderHandle* provider, IdevicePairingFile* pairingFile2, NSString* imagePath, NSString* trustcachePath, NSString* manifestPath, NSError** error) {
    NSData* image = [NSData dataWithContentsOfFile:imagePath];
    NSData* trustcache = [NSData dataWithContentsOfFile:trustcachePath];
    NSData* buildManifest = [NSData dataWithContentsOfFile:manifestPath];
    if(!image || !trustcache || !buildManifest) {
        idevice_pairing_file_free(pairingFile2);
        *error = makeError(1, @"Failed to read one or more DDI files");
        return 1;
    }
    
    LockdowndClientHandle* lockdownClient = 0;
    IdeviceFfiError* err = lockdownd_connect(provider, &lockdownClient);
    if (err) {
        *error = makeError(6, @(err->message));
        idevice_pairing_file_free(pairingFile2);
        idevice_error_free(err);
        return 6;
    }
    
    err = lockdownd_start_session(lockdownClient, pairingFile2);
    idevice_pairing_file_free(pairingFile2);
    if (err) {
        *error = makeError(7, @(err->message));
        idevice_error_free(err);
        return 7;
    }
    
    plist_t uniqueChipIDPlist = 0;
    err = lockdownd_get_value(lockdownClient, "UniqueChipID", 0, &uniqueChipIDPlist);
    if (err) {
        *error = makeError(8, @(err->message));
        idevice_error_free(err);
        return 8;
    }
    
    uint64_t uniqueChipID = 0;
    plist_get_uint_val(uniqueChipIDPlist, &uniqueChipID);
    
    ImageMounterHandle* mounterClient = 0;
    err = image_mounter_connect(provider, &mounterClient);
    if (err) {
        *error = makeError(9, @(err->message));
        idevice_error_free(err);
        return 9;
    }
    
    err = image_mounter_mount_personalized(
        mounterClient,
        provider,
        [image bytes],
        [image length],
        [trustcache bytes],
        [trustcache length],
        [buildManifest bytes],
        [buildManifest length],
        nil,
        uniqueChipID
                                     );
    
    image_mounter_free(mounterClient);
    
    if (err) {
        *error = makeError(10, @(err->message));
        idevice_error_free(err);
        return 10;
    }
    
    return 0;
}
