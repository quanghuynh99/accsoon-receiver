//
//  NaluType.h
//  AccsoonProject
//
//  Created by accsoon app on 2022/4/1.
//  Copyright © 2022 andybain. All rights reserved.
//

#ifndef NaluType_h
#define NaluType_h

typedef enum {
    NaluType_Error              = -1,
    NaluType_IDR                = 5,
    NaluType_NonIDR             = 1,
    NaluType_SPS                = 7,
    NaluType_PPS                = 8,
    NaluType_SEI                = 6,
    NaluType_VPS                = 32,
    NaluType_SPS_PPS            = 100,
}NaluType;

#endif /* NaluType_h */
