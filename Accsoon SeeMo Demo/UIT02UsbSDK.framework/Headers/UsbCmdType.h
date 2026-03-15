//
//  UsbCmdFrameType.h
//  AccsoonWorkProject
//
//  Created by accsoon app on 2022/6/2.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(uint16_t, USBCmdID)
{
    USB_Cmd_Restart             = 3,
    USB_Cmd_Restart_Ack         = (0x8000 | USB_Cmd_Restart),
    
    USB_Cmd_GetVer              = 20,
    USB_Cmd_GetVer_Ack          = (0x8000 | USB_Cmd_GetVer),
    
    USB_Cmd_GetSysInfo          = 21,
    USB_Cmd_GetSysInfo_Ack      = (0x8000 |USB_Cmd_GetSysInfo),
    
    USB_Cmd_SetVideoBitrate     = 40,
    USB_Cmd_SetVideoBitrate_Ack = (0x8000 |USB_Cmd_SetVideoBitrate),
    
    USB_Cmd_GetVidoeBitrate     = 41,
    USB_Cmd_GetVidoeBitrate_Ack = (0x8000 |USB_Cmd_GetVidoeBitrate),

};

#define GetUSBCmdAckCmdID(cmdID)         (uint16_t)(0x8000 | cmdID )

 
