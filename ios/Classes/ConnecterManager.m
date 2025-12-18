//
//  ConnecterManager.m
//  GSDK
//
//

#import "ConnecterManager.h"

@interface ConnecterManager(){
#if !TARGET_OS_SIMULATOR
    ConnectMethod currentConnMethod;
#endif
}
@end

@implementation ConnecterManager

static ConnecterManager *manager;
static dispatch_once_t once;

+(instancetype)sharedInstance {
    dispatch_once(&once, ^{
        manager = [[ConnecterManager alloc]init];
    });
    return manager;
}

/**
 *  方法说明：扫描外设
 *  @param serviceUUIDs 需要发现外设的UUID，设置为nil则发现周围所有外设
 *  @param options  其它可选操作
 *  @param discover 发现的设备
 */
-(void)scanForPeripheralsWithServices:(nullable NSArray<CBUUID *> *)serviceUUIDs options:(nullable NSDictionary<NSString *, id> *)options discover:(void(^_Nullable)(CBPeripheral *_Nullable peripheral,NSDictionary<NSString *, id> *_Nullable advertisementData,NSNumber *_Nullable RSSI))discover{
#if !TARGET_OS_SIMULATOR
    [_bleConnecter scanForPeripheralsWithServices:serviceUUIDs options:options discover:discover];
#endif
}

/**
 *  方法说明：更新蓝牙状态
 *  @param state 蓝牙状态
 */
-(void)didUpdateState:(void(^)(NSInteger state))state {
#if !TARGET_OS_SIMULATOR
    if (_bleConnecter == nil) {
        currentConnMethod = BLUETOOTH;
        [self initConnecter:currentConnMethod];
    }
    [_bleConnecter didUpdateState:state];
#endif
}

-(void)initConnecter:(ConnectMethod)connectMethod {
#if !TARGET_OS_SIMULATOR
    switch (connectMethod) {
        case BLUETOOTH:
            _bleConnecter = [BLEConnecter new];
            _connecter = _bleConnecter;
            break;
        default:
            break;
    }
#endif
}

/**
 *  方法说明：停止扫描
 */
-(void)stopScan {
#if !TARGET_OS_SIMULATOR
    [_bleConnecter stopScan];
#endif
}

/**
 *  连接
 */
-(void)connectPeripheral:(CBPeripheral *)peripheral options:(nullable NSDictionary<NSString *,id> *)options timeout:(NSUInteger)timeout connectBlack:(void(^_Nullable)(ConnectState state)) connectState{
#if !TARGET_OS_SIMULATOR
    [_bleConnecter connectPeripheral:peripheral options:options timeout:timeout connectBlack:connectState];
#endif
}

-(void)connectPeripheral:(CBPeripheral * _Nullable)peripheral options:(nullable NSDictionary<NSString *,id> *)options {
#if !TARGET_OS_SIMULATOR
    [_bleConnecter connectPeripheral:peripheral options:options];
#endif
}

-(void)write:(NSData *_Nullable)data progress:(void(^_Nullable)(NSUInteger total,NSUInteger progress))progress receCallBack:(void (^_Nullable)(NSData *_Nullable))callBack {
#if !TARGET_OS_SIMULATOR
    [_bleConnecter write:data progress:progress receCallBack:callBack];
#endif
}

-(void)write:(NSData *)data receCallBack:(void (^)(NSData *))callBack {
#ifdef DEBUG
    NSLog(@"[ConnecterManager] write:receCallBack:");
#endif
#if !TARGET_OS_SIMULATOR
    _bleConnecter.writeProgress = nil;
    [_connecter write:data receCallBack:callBack];
#endif
}

-(void)write:(NSData *)data {
#ifdef DEBUG
    NSLog(@"[ConnecterManager] write:");
#endif
#if !TARGET_OS_SIMULATOR
    _bleConnecter.writeProgress = nil;
    [_connecter write:data];
#endif
}

-(void)close {
#if !TARGET_OS_SIMULATOR
    if (_connecter) {
        [_connecter close];
    }
    switch (currentConnMethod) {
        case BLUETOOTH:
            _bleConnecter = nil;
            break;
    }
#endif
}

@end
