//
//  PublicMarco.h
//  AccsoonProject
//
//  Created by accsoon app on 2022/4/2.
//  Copyright © 2022 andybain. All rights reserved.
//

#ifndef PubliciOSMacro_h
#define PubliciOSMacro_h

#include "PublicMacro.h"
#import <Foundation/Foundation.h>

#ifndef StringKey
#define StringKey(key) NSLocalizedString(key, nil)
#endif

#ifndef weakObj
#define weakObj(obj) __weak typeof(obj) weak_##obj = obj;
#endif

#ifndef strongObj
#define strongObj(obj) __strong typeof(obj) obj = weak_##obj;
#endif

#ifndef strongObjVaild
#define strongObjVaild(obj) __strong typeof(obj) obj = weak_##obj; if(obj==nil) return;
#endif

#ifndef UIColorHex
#define UIColorHex(color32RGBA)    \
[UIColor colorWithRed:((color32RGBA&0xFF000000)>>24)/255.0 green: ((color32RGBA&0x00FF0000)>>16)/255.0 blue: ((color32RGBA&0x0000FF00)>>8)/255.0 alpha:  ((color32RGBA&0x000000FF)>>0)/255.0]
#endif

#ifndef UIColorRgba
#define UIColorRgba(r,g,b,a) \
[UIColor colorWithRed:(r)/255.0 green: (g)/255.0 blue: (b)/255.0 alpha: (a)/255.0]
#endif




#ifndef IOSStr
#define IOSStr(var) @#var
#endif





#ifdef DEBUG
#import <mach/mach_time.h>
    #define Test_Time_Log(name, code, needPrint)                                        \
                do{                                                                     \
                    mach_timebase_info_data_t info;                                         \
                    uint64_t last, cur;                                                     \
                    last = mach_absolute_time();                                            \
                    code;                                                                   \
                    cur = mach_absolute_time();                                             \
                    if(mach_timebase_info(&info) != KERN_SUCCESS){                          \
                        NSLog(@"error mach_timebase_info");                                 \
                        break;                                                              \
                    }                                                                       \
                    if(needPrint!=false){                                                       \
                        double us =  ( cur-last ) * info.numer /(info.denom*1000.0);        \
                                                                                            \
                        NSLog(@#name"消耗：%.3f ms",  us/1000.0);                                   \
                    }                                                                       \
                }while(0)


    #define CallCodeInterval(timeSec,  code)  \
    do{                                     \
        static NSDate* preDate = nil;       \
        NSDate* curDate = [NSDate date];        \
        if(preDate == nil){                 \
            preDate = curDate;              \
        }else{                              \
            NSTimeInterval interval = [curDate timeIntervalSinceDate: preDate]; \
            if(interval>=timeSec){                                                 \
                preDate = curDate;                                              \
                code;                                                           \
            }                                                                   \
        }\
    }while(0)

    #define PrintCallInterval() \
    do{  \
        static NSDate* begin = nil; \
        NSDate* curDate = [NSDate date]; \
        if(begin == nil){ \
            begin = curDate; \
        }else{ \
            NSTimeInterval interval = [curDate timeIntervalSinceDate: begin]; \
            begin = curDate ;\
            NSLog(@"call interval =%.2f ms", interval*1000.0); \
        }\
    }while(0)

#else
    #define Test_Time_Log(name, code, needPrint) do{                \
        code;                                                       \
    }while(0)

    #define CallCodeInterval(timeSec,  code) code
    #define PrintCallInterval() 
#endif

#ifdef DEBUG
    #define Test_Time(name, code)  Test_Time_Log(name, code, true)
#else
    #define Test_Time(name, code)  Test_Time_Log(name, code, false)
#endif




#ifdef  DEBUG
    #undef  Log

    #define Log(format, ...)        NSLog(format , ##__VA_ARGS__)
 
    #define LogIOS(Tag, format, ...)   \
    do{ \
        NSString* outStr = [[NSString alloc]initWithFormat: @"%@ | " @format, @Tag,  ##__VA_ARGS__]; \
        NSLog(@"%@", outStr); \
    }while(0)

    #undef LOG
    #define LOG(format, ...) NSLog(@format, ##__VA_ARGS__)

    #ifndef PrintFunName
    #define PrintFunName     NSLog(@"%s-----", __FUNCTION__)
    #endif
    
    #ifndef DDLogDebug
    #define DDLogDebug(format,  ...) NSLog(format, ##__VA_ARGS__)
    #endif
#else //release 版本
    #undef  NSLog
    #define NSLog(format, ...)
    
    #undef  Log
    #define Log(format, ...)
    #undef  LogIOS
    #define LogIOS(Tag, format, ...)
    #undef  LOG
    #define LOG(format, ...)
    #undef  PrintFunName
    #define PrintFunName

    #undef  DDLogDebug
    #define DDLogDebug(format,  ...)
#endif


#ifndef DispatchResume
#define DispatchResume(obj, isTimerSuspend)  if(obj && isTimerSuspend==YES){ dispatch_resume(obj); isTimerSuspend=NO;}
#endif

#ifndef DispatchSuspend
#define DispatchSuspend(obj, isTimerSuspend) if(obj && isTimerSuspend==NO){ dispatch_suspend(obj); isTimerSuspend=YES;}
#endif

#endif /* PublicMarco_h */
