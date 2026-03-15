//
//  RtmsuTypes.h
//  AccsoonWorkProject
//
//  Created by accsoon app on 2022/4/28.
//

 
#import <Foundation/Foundation.h>
#import <ExternalAccessory/ExternalAccessory.h>
#import "CodecType.h"
#import "NaluType.h"
#import "UsbCmdType.h"

typedef NS_ENUM(int, MediaType)
{
    MediaType_None = 0,
    MediaType_Video,
    MediaType_Audio
};

@class AccessoryManager;
 

///Warning: AccessoryListener all block callback in main thread.
@interface AccessoryListener : NSObject

/// callback  when the cable between the hardware and the phone is unplugged
@property(nonatomic,copy) void(^accessoryPullout)(AccessoryManager* manager);

/// callback when the cable between the hardware and the phone is plugged in
@property(nonatomic,copy) void(^accessoryPlugIn)(AccessoryManager* manager);

/// callback when a hardware is found.   msg is about  hardware info(hardware version ...)
@property(nonatomic,copy) void(^accessoryMessage)(NSString* msg);
@end



/// Rtmsu means Real-time media stream  USB.   Warning:    all block callback in library inner thread， take care of thread safety yourself
@interface RtmsuListener : NSObject

/// callback  when has a video channel,   param about video info  (our hardware  codeType always be MEDIA_CODE_TYPE_PT_H264, maxWid is 1920, maxHei is 1080)
@property(nonatomic,copy) void(^videoChannelHandler)(MediaCodecType codeType, uint32_t maxWid, uint32_t maxHei);

/// callback when H264 data come in,   nalu has a four byte or three byte startcode(0x00 0x00 0x00 0x01 or 0x00 0x00 0x01)， a byte nalu header,   other are RBSP
/// timestamp  unit  is  microsecond（ 1/1000000 seconds )
/// codeWid codeHei is code video resolution (acrroding input video source, support 1080p and 720p)
/// fps   stands for the number of image frames displayed per second.  If the input is 1080i60 fps, it will display 30.
/// nalu type indicate the nalu type, you can see NaluType.h file. （In particular,  when type is NaluType_SPS_PPS,  nalu data  is a combination of sps pps nalu）
/// canDiscard is YES  means that you can discard this nalu without affecting the decoding. if you discard all nalu that canDiscard is YES,  the fps will become half of the input source.  you can dynamically discard Nalu on some poor performance phones
/// isIFormat   indicates whether the input video is in interlaced format.
/// Warning: nalu conatinas  a inner pointer to  library-managed memory. If you want to do something else with the data, copy the memory data yourself
/// The frequency at which the videoDataHandler is called depends on the input HDMI video source's fps, which is usually 60HZ and 30HZ
///
@property(nonatomic,copy) void(^videoDataHandler)(NSMutableData* nalu, uint64_t timestamp, uint16_t codeWid, uint16_t codeHei, uint8_t fps, NaluType type, BOOL canDiscard,BOOL isIFormat);

/// callback when has a audio channel,  param about audio info (our hardware codecType always be MEDIA_CODE_TYPE_PT_AAC
/// channelMode is 1 means Stereo, 0 means  Mono. sampleRate is 48000, bitwidth is 1 menas 16bit for one channel, 0 means 8bit for one channel  for our hardware
@property(nonatomic,copy) void(^audioChannelHandler)(MediaCodecType codeType, uint8_t channelMode, uint32_t sampleRate, uint8_t bitwidth);

/// callback when aac data come in,  adts  means aac format is ADTS,   adts consists of  ADTS Header and  AAC ES
/// timestamp unit is microsecond （ 1/1000000 seconds )
/// Warning: adts conatinas  a inner pointer to  library-managed memory. If you want to do something else with the data, copy the memory data yourself
/// The callback frequency of audioDataHandler is about 46.8HZ. Because the sampling rate of the hardware output is 48KHz, the adts contains 1024 samples.
/// Therefore, the playback time of each adts data is 1024/48000 = 0.02133 seconds, so the callback frequency of  audioDataHandler is 1/0.02133 = 46.8HZ.
@property(nonatomic,copy) void(^audioDataHandler)(NSMutableData* adts, uint64_t timestamp);

/// callback when an exception occurs . Most of the time  the  block will not be callback because usb communication is more stable
@property(nonatomic,copy) void(^rtmsuDisconnectHandler)(void);


/// callback when  video  or audio lost frame,  ervery video/audio frame has  a frame index, frame index is increasing.  video/audio frame index is independent
/// type indicate who lost frame, video or audio
/// lastFrameIndex  is last frame's index, curFrameIndex is curent frame's index.    you can use   curFrameIndex - lastFrameIndex get  how many frames  lost.
@property(nonatomic,copy) void(^audioVideoDropFrameReport)(MediaType type,  uint64_t lastFrameIndex, uint64_t curFrameIndex);


@end


///  Warning:    all block callback in library inner thread， take care of thread safety yourself
///  info about payload format, you can see  UIT02 command between APP and Hardware.pdf file
@interface CmdListener: NSObject

/// callback when  hardware send command to app.    If you want to listen to all the commands that the hardware sends to the app, you can set it. Otherwise you don't need to set up this listener
@property(nonatomic,copy) void(^cmdRecvHandler)(USBCmdID cmdID, NSData* payload);
@end


///  Warning:  USBDelegateStateListener  all block callback in main thread.
@interface USBDelegateStateListener : NSObject
/// callback when usb thread  into working
@property(nonatomic,copy) void(^usbDelegateDidIntoWork)(void);

/// callback when usb thread finish working
@property(nonatomic,copy) void(^usbDelegateDidFinishWork)(void);
@end

 
