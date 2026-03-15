//
//  RtmsuDelegate.h
//  AccsoonWorkProject
//
//  Created by accsoon app on 2022/4/27.
//

#import <Foundation/Foundation.h>
#import <ExternalAccessory/ExternalAccessory.h>
#import "ListenerType.h"


@interface USBDelegate : NSObject <NSStreamDelegate>
 
 
-(id)initWithEASession:(EASession*)session;

-(BOOL)isWorkVaild;

/// set listener for USBDelegate state changed.
/// - Parameter listener: listener, you can see USBDelegateStateListener define
-(void)setStateListener:(USBDelegateStateListener*)listener;

/// set listener for video/audio data, channel info ...    if  you  use [startUsbThreadOnlyForCmd: YES ], you do't need  set Media listener
/// - Parameter listener: listener, you can see RtmsuListener define
-(void)setRtmsuListener:(RtmsuListener*) listener;


/// set listener for command data sent by hardware to app
/// - Parameter listener: listener.cmdRecvHandler will called for all command. you can see CmdListener define
-(void)setCmdListener:(CmdListener*)listener;
 
/// start  get video audio/sending command  thread loop
/// - Parameter onlyCmd: onlyCmd is YES means start work  just for sending/receive command, no video and audio com in (sometimes in some ViewController you just want get some hardware's info to show for user,  don't display video )
/// (it just use for get the hardware's system info, set hardware's video bitrate, update hardware  firmware ... you can see UsbCmdType.h file  );
/// onlyCmd is NO means start work for getting  video audio  and  also  sending/receive command.
-(void)startUsbThreadOnlyForCmd:(BOOL)onlyCmd;

/// stop get video audio/sending command thread loop     when you quit from ViewController that  created USBDelegate object,  you should call  stopUsbThread
-(void)stopUsbThread;

/// send command to hardware without callback.  return YES just mean you write to outputStream successfully.
/// - Parameters:
///   - cmdID: custom command ID, you can see UsbCmdType.h file
///   - data:  it is different  according to cmdID value, sometimes is nil if no need data
-(BOOL)usbSendCmd:(USBCmdID)cmdID payload:(NSData*) data;

/// send command to hardware with callback.  return YES just mean you write to outputStream successfully.
/// - Parameters:
///   - cmdID: custom command ID, you can see UsbCmdType.h file
///   - data:  it is different  according to cmdID value, sometimes is nil if no  data
///   - handler: callback called in inner thread,  if you want do something about UI or something spend much time , you should post to UI thread or other thread.
-(BOOL)usbSendCmd:(USBCmdID)cmdID payload:(NSData*)data handler:(void (^)(USBCmdID returnCmdID, NSData* data)) handler;
@end

 
