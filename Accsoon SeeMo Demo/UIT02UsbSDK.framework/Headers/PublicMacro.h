//
//  PublicMacro.h
//  AccsoonProject
//
//  Created by accsoon app on 2022/4/2.
//  Copyright © 2022 andybain. All rights reserved.
//

#ifndef PublicMacro_h
#define PublicMacro_h

#ifndef SafeFree
#define SafeFree(var) do{ if(var!=NULL){ free(var); } }while(0)
#endif


#ifndef ColorRgba
#define ColorRgba(r,g,b,a) (unsigned int)(r<<0|g<<8|b<<16|a<<24)
#endif

#ifndef CStr
#define CStr(var) #var
#endif
#ifndef SHADER_STRING
#define SHADER_STRING CStr
#endif


#ifndef OutConn
#define OutConn(v1, v2) Conn(v1, v2)
#endif

#ifndef Conn
#define Conn(v1, v2) v1##v2
#endif


#ifndef RedValue
#define RedValue(value)    (0x000000FF & (value >>0))
#endif
#ifndef GreenValue
#define GreenValue(value)  (0x000000FF & (value >>8))
#endif
#ifndef BlueValue
#define BlueValue(value)   (0x000000FF & (value >>16))
#endif
#ifndef AlphaValue
#define AlphaValue(value)   (0x000000FF & (value >>24))
#endif

#ifndef Red16Value
#define Red16Value(value)    (0x000000000000FFFF & (value >>0))
#endif
#ifndef Green16Value
#define Green16Value(value)  (0x000000000000FFFF & (value >>16))
#endif
#ifndef Blue16Value
#define Blue16Value(value)   (0x000000000000FFFF & (value >>32))
#endif
#ifndef Alpha16Value
#define Alpha16Value(value)   (0x000000000000FFFF & (value >>48))
#endif

#endif /* PublicMacro_h */
