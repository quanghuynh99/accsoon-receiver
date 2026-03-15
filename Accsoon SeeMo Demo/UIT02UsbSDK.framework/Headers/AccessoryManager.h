//
//  AccessoryManager.h
//  AccsoonProject
//
//  Created by accsoon app on 2022/4/26.
//  Copyright © 2022 andybain. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "USBDelegate.h"
#import "ListenerType.h"
 

/// AccessoryManager is a class that create USBDelegate which can communicate with hardware
@interface AccessoryManager : NSObject

/// 
/// - Parameter listener: init with AccessoryListener.    see   ListenerType.h
-(id)initWithListener:(AccessoryListener*) listener;


-(USBDelegate*)scanAndCreateDeviceDelegate;

/// when you quit  form ViewController that created AccessoryManager object ,    you should call this method to clear inner resource
-(void)clear;
@end

 
