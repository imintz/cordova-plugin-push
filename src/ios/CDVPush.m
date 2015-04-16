/*
 Licensed to the Apache Software Foundation (ASF) under one
 or more contributor license agreements.  See the NOTICE file
 distributed with this work for additional information
 regarding copyright ownership.  The ASF licenses this file
 to you under the Apache License, Version 2.0 (the
 "License"); you may not use this file except in compliance
 with the License.  You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing,
 software distributed under the License is distributed on an
 "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 KIND, either express or implied.  See the License for the
 specific language governing permissions and limitations
 under the License.
 */

#import <Cordova/CDV.h>
#import "CDVPush.h"
#import <JavaScriptCore/JavaScriptCore.h>
#import <objc/runtime.h>

NSString *DEVICE_TOKEN_STORAGE_KEY;
CDVPush *this;

@implementation CDVPush

@synthesize completionHandler;
@synthesize serviceWorker;

- (void)setupPush:(CDVInvokedUrlCommand*)command
{
    DEVICE_TOKEN_STORAGE_KEY = @"CDVPush_devicetoken";
    self.serviceWorker = [self.commandDelegate getCommandInstance:@"ServiceWorker"];
    [self setupPushHandlers];
    [self setupSyncResponse];

    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

- (void)setupPushHandlers
{
    this = self;
    if ([[[UIApplication sharedApplication] delegate] respondsToSelector:@selector(application:didReceiveRemoteNotification:)]) {
        Method original, swizzled;
        original = class_getInstanceMethod([self class], @selector(application:didReceiveRemoteNotification:));
        swizzled = class_getInstanceMethod([[[UIApplication sharedApplication] delegate] class], @selector(application:didReceiveRemoteNotification:));
        method_exchangeImplementations(original, swizzled);
    } else {
        class_addMethod([[[UIApplication sharedApplication] delegate] class], @selector(application:didReceiveRemoteNotification:), class_getMethodImplementation([self class], @selector(application:didReceiveRemoteNotification:)), nil);
    }
    if ([[[UIApplication sharedApplication] delegate] respondsToSelector:@selector(application:didReceiveRemoteNotification:fetchCompletionHandler:)]) {
        Method original, swizzled;
        original = class_getInstanceMethod([self class], @selector(application:didReceiveRemoteNotification:fetchCompletionHandler:));
        swizzled = class_getInstanceMethod([[[UIApplication sharedApplication] delegate] class], @selector(application:didReceiveRemoteNotification:fetchCompletionHandler:));
        method_exchangeImplementations(original, swizzled);
    } else {
        class_addMethod([[[UIApplication sharedApplication] delegate] class], @selector(application:didReceiveRemoteNotification:fetchCompletionHandler:), class_getMethodImplementation([self class], @selector(application:didReceiveRemoteNotification:fetchCompletionHandler:)), nil);
    }
}

- (void)hasPermission:(CDVInvokedUrlCommand*)command
{
    @try {
        if ([self hasPermission]) {
            CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"granted"];
            [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
        } else {
            CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"denied"];
            [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
        }
    }
    @catch (NSException *exception) {
        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[exception description]];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
    }
}

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo
{
    NSLog(@"Received remote notification");
    [this dispatchPushEvent:userInfo];
}

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler
{
    NSLog(@"Received background remote notification");
    this.completionHandler = completionHandler;
    [this dispatchPushEvent:userInfo];
}

- (void)dispatchPushEvent:(NSDictionary*) userInfo
{
    NSError *error;
    NSData *json = [NSJSONSerialization dataWithJSONObject:userInfo options:0 error:&error];
    NSString *dispatchCode = [NSString stringWithFormat:@"FirePushEvent(%@);", [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]];
    [this.serviceWorker.context performSelectorOnMainThread:@selector(evaluateScript:) withObject:dispatchCode waitUntilDone:NO];
}

- (void)setupSyncResponse
{
    __weak CDVPush *weakSelf = self;
    serviceWorker.context[@"sendSyncResponse"] = ^(JSValue *responseType) {
        UIBackgroundFetchResult result;
        switch ([responseType toInt32]) {
            case 0:
                result = UIBackgroundFetchResultNewData;
                break;
            case 1:
                result = UIBackgroundFetchResultFailed;
                break;
            default:
                result = UIBackgroundFetchResultNoData;
                break;
        }
        if (weakSelf.completionHandler != nil) {
            weakSelf.completionHandler(result);
            weakSelf.completionHandler = nil;
        }
    };
}

- (void)storeDeviceToken:(CDVInvokedUrlCommand*)command
{
    NSString *deviceToken = [command argumentAtIndex:0];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:deviceToken forKey:DEVICE_TOKEN_STORAGE_KEY];
    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

- (void)getDeviceToken:(CDVInvokedUrlCommand*)command
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *token = [defaults objectForKey:DEVICE_TOKEN_STORAGE_KEY];
    if (token != nil) {
        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:token];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
    } else {
        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"No Subscription"];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
    }
}

- (BOOL)hasPermission
{
    if ([[UIApplication sharedApplication] respondsToSelector:@selector(isRegisteredForRemoteNotifications)])
    {
        return [[UIApplication sharedApplication] isRegisteredForRemoteNotifications];
    } else {
        return [[UIApplication sharedApplication] enabledRemoteNotificationTypes] != UIRemoteNotificationTypeNone;
    }
}

//This method is meant for testing purposes. It simulates a notification event
- (void)simulateNotification:(CDVInvokedUrlCommand*)command
{
    NSDictionary *dictionary = @{
                                 @"data" : @(5)
                                 };
    [[[UIApplication sharedApplication] delegate] application:[UIApplication sharedApplication] didReceiveRemoteNotification:dictionary];
}
@end

