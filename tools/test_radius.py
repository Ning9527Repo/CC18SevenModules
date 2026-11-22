"""Execute the shipped C geometry and validate four native slider integration.
Not a UIKit/device test. macOS also compiles the actual extracted specifier code.
"""
import json,subprocess,tempfile,os,re,platform
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

def main():
 bridge=(ROOT/'Settings/C18SettingsBridge.m').read_text()
 radius=(ROOT/'C18Radius.m').read_text()
 prefs=(ROOT/'C18RadiusPreferences.h').read_text()
 control=(ROOT/'Settings/C18EnableControl.m').read_text()
 keys=['RadiusConnectivity','RadiusPlayer','RadiusSliders','RadiusOther']
 assert all(prefs.count('@"'+key+'"')==1 for key in keys)
 for name in ('连接模块圆角','播放器圆角','音量与亮度圆角','其他模块圆角'):assert name in bridge
 for token in ('cell:5 edit:Nil','@selector(setRadius:specifier:)','@selector(readRadius:)','indexOfObjectIdenticalTo:spec','result[toggleIndex+1+i]==state.sliders[i]','insertObjects:state.sliders atIndexes:indexes'):
  assert token in bridge,token
 for token in ('@"min"','@"max"','@"continuous"','@"showValue"'):assert token in bridge
 assert 'CFSTR(C18_RADIUS_DOMAIN)' in control and 'notify_post(C18_RADIUS_NOTIFY)' in control
 assert 'C18RadiusKnownKey(key)' in control and 'isfinite([value doubleValue])' in control
 assert 'expanded || C18RadiusSingle(size,cols,rows,NO)' in radius
 assert 'C18_RADIUS_INSTALL(Module,"C18ModuleView")' in radius
 assert 'gDone##NAME=YES;MSHookMessageEx' in radius
 for token in ('MSHookFunction','setFrame:','setBounds:','setTransform:','UIImageView','respring','kill('):assert token not in radius,token
 assert 'C18RadiusSurfaces(view,NO,0);\n    ((void(*)(id,SEL))original)(view,cmd);' in radius
 assert '[CATransaction setDisableActions:YES]' in radius
 code=r'''
#include "C18RadiusGeometry.h"
#include <assert.h>
#include <stdio.h>
int main(void){
 long columns[9]={1,1,2,4,2,4,4,4,4},rows[9]={1,2,1,1,2,8,2,4,6};
 unsigned checks=0;
 for(long i=0;i<9;i++)for(int expanded=0;expanded<2;expanded++){
  assert(C18RadiusSingle(i,columns[i],rows[i],expanded)==(i==0&&!expanded));checks++;
 }
 assert(!C18RadiusSingle(4,2,2,0));assert(C18RadiusSingle(0,0,0,0));
 for(int w=20;w<501;w+=7)for(int h=20;h<801;h+=11){
  double native=fmin(w,h)*0.225,max=fmin(w,h)*0.5,previous=native;
  for(int p=0;p<=100;p++){
   double r=C18RadiusInterpolate(native,w,h,p);
   assert(r>=native-1e-10&&r<=max+1e-10&&r>=previous-1e-10);
   if(!p)assert(r==native);
   if(p==100)assert(fabs(r-max)<1e-10);
   previous=r;checks++;
  }
 }
 assert(C18RadiusPercent(NAN)==0);assert(C18RadiusPercent(INFINITY)==0);
 assert(C18RadiusPercent(-10)==0);assert(C18RadiusPercent(101)==100);
 assert(C18RadiusInterpolate(24,0,100,80)==24);
 assert(C18RadiusInterpolate(24,100,100,0)==24);
 printf("RADIUS_PRODUCTION_GEOMETRY_OK %u\n",checks);
 return 0;
}
'''
 with tempfile.TemporaryDirectory(prefix='cc18-radius-tests-',dir='/tmp') as temp:
  path=Path(temp);(path/'test.c').write_text(code)
  subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror','-I'+str(ROOT),str(path/'test.c'),'-lm','-o',str(path/'test')],check=True)
  subprocess.run([str(path/'test')],check=True)
 # Exercise the native mutable-list identity policy with inserted system rows,
 # repeated loads, partial cached rows, immutable input, and four slider rows.
 cases=0
 for before in range(16):
  original=[object() for _ in range(before)];group=object();toggle=object();sliders=[object() for _ in range(4)]
  for partial in range(64):
   rows=original+[x for j,x in enumerate([group,toggle]+sliders) if partial&(1<<j)]
   for repeat in range(6):
    hg=group in rows;ht=toggle in rows
    if hg!=ht:rows=[x for x in rows if x is not group and x is not toggle];hg=False
    if not hg:rows.extend([group,toggle])
    ti=rows.index(toggle)
    ordered=rows[ti+1:ti+5]==sliders
    if not ordered:
     rows=[x for x in rows if x not in sliders];ti=rows.index(toggle);rows[ti+1:ti+1]=sliders
    assert rows[:before]==original
    assert rows[rows.index(toggle)+1:rows.index(toggle)+5]==sliders
    assert all(rows.count(x)==1 for x in [group,toggle]+sliders)
    cases+=1
 print('RADIUS_FOUR_SLIDER_INTEGRATION_OK',json.dumps({'list_cases':cases,'groups':4,'default':0,'max':100,'runtime_tested':False}))
if __name__=='__main__':main()
