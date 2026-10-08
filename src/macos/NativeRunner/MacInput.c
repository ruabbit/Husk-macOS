/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "MacInput.h"
#include <string.h>
#include <math.h>
void mac_input_clear(MacInput *input) { memset(input,0,sizeof(*input)); }
void mac_input_key(MacInput *input, unsigned code, bool down)
{
    if(code<128)input->keys[code]=down;
    if(code==15 && down)input->value.restart=1;
    if(down)input->value.pointerDown=0;
}
void mac_input_pointer(MacInput *input,float x,float y,float width,float height,bool down)
{
    if(!isfinite(x)||!isfinite(y)||width<=0||height<=0) {input->value.pointerDown=0;return;}
    float scale=fminf(width/640,height/400), left=(width-640*scale)/2, top=(height-400*scale)/2;
    float px=(x-left)/scale, py=(y-top)/scale;
    input->value.pointerDown=down && px>=0 && px<=640 && py>=0 && py<=400;
    input->value.pointerX=fminf(640,fmaxf(0,px)); input->value.pointerY=fminf(400,fmaxf(0,py));
}
void mac_input_controller(MacInput *input,float x,float y,bool restart)
{
    input->padX=isfinite(x)&&fabsf(x)>.15f ? fminf(1,fmaxf(-1,x)):0;
    input->padY=isfinite(y)&&fabsf(y)>.15f ? -fminf(1,fmaxf(-1,y)):0;
    if(input->padX||input->padY)input->value.pointerDown=0;
    if(restart)input->value.restart=1;
}
OrbitInput mac_input_frame(MacInput *input)
{
    OrbitInput value=input->value; input->value.restart=0;
    value.x=fminf(1,fmaxf(-1,(input->keys[124]||input->keys[2])-(input->keys[123]||input->keys[0])+input->padX));
    value.y=fminf(1,fmaxf(-1,(input->keys[125]||input->keys[1])-(input->keys[126]||input->keys[13])+input->padY));
    return value;
}
