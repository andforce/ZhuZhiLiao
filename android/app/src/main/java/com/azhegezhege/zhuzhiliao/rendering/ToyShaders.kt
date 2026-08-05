package com.azhegezhege.zhuzhiliao.rendering

object ToyShaders {
    const val BACKGROUND_VERTEX = """#version 300 es
        precision highp float;
        out vec2 vUv;
        void main() {
            vec2 positions[3] = vec2[3](vec2(-1.0,-1.0),vec2(3.0,-1.0),vec2(-1.0,3.0));
            vec2 p = positions[gl_VertexID];
            gl_Position = vec4(p,0.999,1.0);
            vUv = p * 0.5 + 0.5;
        }
    """

    const val BACKGROUND_FRAGMENT = """#version 300 es
        precision highp float;
        in vec2 vUv;
        out vec4 outColor;
        uniform vec2 uViewport;
        uniform float uTime;
        uniform float uActivity;
        uniform float uTheme;
        uniform vec3 uSkyTop;
        uniform vec3 uSkyMiddle;
        uniform vec3 uSkyBottom;
        uniform vec3 uAtmosphere;
        uniform vec3 uAccent;
        uniform vec3 uSilhouette;

        float hash21(vec2 p){p=fract(p*vec2(123.34,456.21));p+=dot(p,p+45.32);return fract(p.x*p.y);}
        float segmentDistance(vec2 p,vec2 a,vec2 b){vec2 s=b-a;float d=max(dot(s,s),.00001);float t=clamp(dot(p-a,s)/d,0.,1.);return length(p-(a+s*t));}
        float softStroke(vec2 p,vec2 a,vec2 b,float w,float aspect){vec2 q=vec2(aspect,1.);return 1.-smoothstep(w,w+.004,segmentDistance(p*q,a*q,b*q));}
        float aspectDistance(vec2 p,vec2 c,float aspect){return length((p-c)*vec2(aspect,1.));}
        float particleField(vec2 uv,float aspect,float time,vec2 grid,float speed,float threshold,float size,float drift){
            vec2 a=uv+vec2(sin(time*.17+uv.y*8.)*drift,time*speed);vec2 cell=floor(a*grid);vec2 local=fract(a*grid);
            float random=hash21(cell+3.71);vec2 center=vec2(hash21(cell+8.13),hash21(cell+15.77));
            return (1.-smoothstep(size,size*1.8,length((local-center)*vec2(aspect,1.))))*step(threshold,random);
        }
        void main(){
            vec2 uv=vec2(vUv.x,1.-vUv.y);float aspect=max(uViewport.x/max(uViewport.y,1.),.1);
            vec3 color=mix(uSkyTop,uSkyMiddle,smoothstep(0.,.58,uv.y));color=mix(color,uSkyBottom,smoothstep(.56,1.04,uv.y));
            float haze=exp(-pow((uv.y-.70)*4.3,2.));color+=uAtmosphere*haze*.12;
            if(uTheme<.5){
                float d=aspectDistance(uv,vec2(.79,.20),aspect);float glow=1.-smoothstep(.035,.18,d);float sun=1.-smoothstep(.040,.048,d);
                color+=uAccent*glow*.12;color=mix(color,vec3(.94,.84,.64),sun*.82);
                float s=0.;s+=softStroke(uv,vec2(-.03,.05),vec2(.18,.37),.010,aspect);s+=softStroke(uv,vec2(.06,.18),vec2(.11,.54),.004,aspect);s+=softStroke(uv,vec2(.13,.26),vec2(.22,.58),.003,aspect);s+=softStroke(uv,vec2(1.02,.02),vec2(.88,.31),.007,aspect);
                color=mix(color,uSilhouette,clamp(s,0.,1.)*.76);color+=uAccent*particleField(uv,aspect,uTime,vec2(12.,21.),-.022,.88,.070,.010)*.68;
            }else if(uTheme<1.5){
                float d=aspectDistance(uv,vec2(.80,.18),aspect);float glow=1.-smoothstep(.035,.17,d);float moon=1.-smoothstep(.043,.051,d);float cut=1.-smoothstep(.038,.049,aspectDistance(uv,vec2(.823,.164),aspect));
                color+=uAccent*glow*.12;color=mix(color,vec3(.94,.90,.70),moon*(1.-cut)*.90);
                float s=0.;s+=softStroke(uv,vec2(-.02,1.04),vec2(.10,.42),.014,aspect);s+=softStroke(uv,vec2(.055,.66),vec2(.20,.56),.006,aspect);s+=softStroke(uv,vec2(1.02,1.02),vec2(.93,.47),.013,aspect);s+=softStroke(uv,vec2(.96,.67),vec2(.83,.58),.006,aspect);
                color=mix(color,uSilhouette,clamp(s,0.,1.)*.76);vec2 cell=floor(uv*vec2(11.,20.));float r=hash21(cell+19.1);vec2 c=(cell+vec2(hash21(cell+5.2),hash21(cell+9.8)))/vec2(11.,20.);
                float fly=(1.-smoothstep(.002,.008,aspectDistance(uv,c,aspect)))*step(.83,r);float pulse=.35+.65*pow(.5+.5*sin(uTime*(.7+r)+r*20.),3.);color+=uAccent*fly*pulse;
            }else if(uTheme<2.5){
                float d=aspectDistance(uv,vec2(.77,.22),aspect);color+=uAccent*(1.-smoothstep(.050,.22,d))*.16;color=mix(color,vec3(.98,.74,.37),(1.-smoothstep(.070,.080,d))*.88);
                float farR=.77+sin(uv.x*8.+.6)*.035+sin(uv.x*17.)*.018;float nearR=.86+sin(uv.x*6.+2.1)*.055+sin(uv.x*13.)*.022;
                color=mix(color,uSilhouette*1.7,smoothstep(farR,farR+.025,uv.y)*.56);color=mix(color,uSilhouette,smoothstep(nearR,nearR+.020,uv.y)*.86);
                color+=uAccent*particleField(uv,aspect,uTime,vec2(11.,19.),-.035,.86,.080,.018)*.68;
            }else{
                float d=aspectDistance(uv,vec2(.82,.19),aspect);color+=uAccent*(1.-smoothstep(.045,.17,d))*.14;color=mix(color,vec3(.90,.86,.72),(1.-smoothstep(.044,.052,d))*.92);
                float s=0.;s+=softStroke(uv,vec2(-.02,1.06),vec2(.060,.42),.012,aspect);s+=softStroke(uv,vec2(.052,.68),vec2(.18,.58),.007,aspect);s+=softStroke(uv,vec2(.020,.82),vec2(-.045,.75),.005,aspect);s+=softStroke(uv,vec2(1.03,1.06),vec2(.955,.44),.011,aspect);s+=softStroke(uv,vec2(.973,.69),vec2(.86,.59),.006,aspect);
                color=mix(color,uSilhouette,clamp(s,0.,1.)*.88);color+=uAccent*particleField(uv,aspect,uTime,vec2(16.,29.),-.028,.88,.050,.006)*.78;
            }
            float activityGlow=1.-smoothstep(.03,.34,aspectDistance(uv,vec2(.50,.50),aspect));color+=uAccent*uActivity*activityGlow*.16;
            color+=uAtmosphere*exp(-pow((uv.y-1.03)*2.5,2.))*.11;float vignette=smoothstep(.80,.20,aspectDistance(uv,vec2(.5,.48),aspect));color*=.72+vignette*.32;
            float grain=hash21(floor(uv*uViewport)*.73)-.5;color+=grain*.007;outColor=vec4(color,1.);
        }
    """

    const val LIT_VERTEX = """#version 300 es
        precision highp float;
        layout(location=0) in vec3 aPosition;
        layout(location=1) in vec3 aNormal;
        layout(location=2) in vec3 aTexture;
        uniform mat4 uViewProjection;
        uniform mat4 uModel;
        out vec3 vNormal;
        out vec3 vTexture;
        void main(){gl_Position=uViewProjection*uModel*vec4(aPosition,1.);vNormal=normalize(mat3(transpose(inverse(uModel)))*aNormal);vTexture=aTexture;}
    """

    const val LIT_FRAGMENT = """#version 300 es
        precision highp float;
        in vec3 vNormal;in vec3 vTexture;out vec4 outColor;
        uniform vec4 uBaseColor;uniform vec2 uMaterial;uniform vec3 uCoolLight;uniform vec3 uWarmLight;
        void main(){
            vec3 normal=normalize(vNormal);vec3 moon=normalize(vec3(.55,.78,.60));vec3 warmDir=normalize(vec3(-.62,.18,.74));vec3 viewDir=normalize(vec3(0.,.04,1.));vec3 halfDir=normalize(moon+viewDir);
            float diffuse=max(dot(normal,moon),0.);float rim=pow(1.-max(dot(normal,viewDir),0.),2.7);float warm=max(dot(normal,warmDir),0.);
            vec3 base=uBaseColor.rgb;float kind=uMaterial.x;vec2 uv=vTexture.xy;float surface=vTexture.z;float rough=.78;
            if(kind>.5&&kind<1.5){float fine=sin(uv.x*238.+sin(uv.y*15.)*2.4);float broad=sin(uv.x*31.+uv.y*5.+.8);float m=sin(uv.y*11.+sin(uv.x*19.))*.5+.5;base*=.91+fine*.022+broad*.055+m*.025;rough=.88;if(surface>.5&&surface<1.5){base*=.34+m*.10;rough=.96;}else if(surface>1.5){vec2 c=uv-.5;float ray=sin(atan(c.y,c.x)*44.+length(c)*38.);float ring=sin(length(c)*112.);base*=1.08+ray*.025+ring*.018;rough=.94;}}
            else if(kind>1.5&&kind<2.5){vec2 c=uv-.5;float radial=sin(atan(c.y,c.x)*38.+length(c)*90.);float ring=sin(length(c)*118.+radial*.3);base*=.98+radial*.018+ring*.012;rough=.93;}
            else if(kind>2.5&&kind<3.5){base+=sin(uv.x*17.)*.018;rough=.28;}
            else if(kind>3.5&&kind<4.5){base*=.88+sin((uv.x*33.+uv.y*19.)*6.2831853)*.055;rough=.82;}
            else if(kind>4.5&&kind<5.5){float across=abs(uv.x-.5);float center=1.-smoothstep(.016,.043,across);float bc=uv.y*5.8+across*1.42;float bd=min(fract(bc),1.-fract(bc));float side=(1.-smoothstep(.018,.060,bd))*smoothstep(.055,.17,across);float edge=smoothstep(.435,.495,across);float vein=max(center*.82,max(side*.38,edge*.34));base*=.94+sin(uv.y*28.+uv.x*3.)*.025;base=mix(base,base*.58,vein);rough=.90;}
            else if(kind>5.5&&kind<6.5){vec2 c=uv-.5;float radial=sin(atan(c.y,c.x)*52.+length(c)*15.);float paper=sin(uv.x*153.+sin(uv.y*71.)*1.8)+sin(uv.y*197.+uv.x*8.)*.55;float age=smoothstep(.32,.50,length(c));base*=.96+radial*.012+paper*.012-age*.075;rough=.98;}
            float specPower=mix(10.,74.,1.-rough);float spec=pow(max(dot(normal,halfDir),0.),specPower)*mix(.03,.42,1.-rough);
            vec3 light=uCoolLight*.25+vec3(1.,.92,.75)*diffuse*.88+uWarmLight*warm*.18+uCoolLight*rim*.22;
            vec3 color=base*light+uWarmLight*spec+base*uMaterial.y*mix(uCoolLight,uWarmLight,.55);outColor=vec4(color,uBaseColor.a);
        }
    """
}
