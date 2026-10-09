'use strict';
(function(root){
const DEFAULT={radius:.22,bodyHeight:1.7,maxJumpRise:1.35,maxJumpDistance:3,stepHeight:.15};
const EPS=1e-6;
function rule(kind){if(/箱|crate/i.test(kind))return {kind:'crate',height:.8,solid:true,standable:true};if(/水|海|绿洲|ocean|water/i.test(kind))return {kind:'water',height:0,solid:false,standable:false};if(/树|杉|松|棕榈|金合欢|tree/i.test(kind))return {kind:'tree',height:4,solid:true,standable:false};if(/岩|石|rock/i.test(kind))return {kind:'rock',height:.65,solid:true,standable:true};if(/草|花|蘑菇|蕨|地衣|苔藓/.test(kind))return {kind:'foliage',height:0,solid:false,standable:false};return {kind:'obstacle',height:2.2,solid:true,standable:false};}
function attach(m){if(m.physics?.version===1){validate(m);return m;}const surfaces=[],covered=new Set(),grid=m.layers.collision.slice();
for(const o of m.layers.objects){const r=o.footprint?{kind:'building',height:4,solid:true,standable:false}:rule(o.kind);const f=o.collision?.bounds||o.footprint||{x:o.x+.15,y:o.y+.15,width:.7,height:.7};const s={id:o.id||'object-'+surfaces.length,objectId:o.id,x:f.x,y:f.y,width:f.width,depth:f.height,...r,baseZ:0};if(o.collision){s.height=o.collision.height??s.height;s.standable=o.collision.standable??s.standable;s.solid=o.collision.solid??s.solid;}surfaces.push(s);for(let y=Math.floor(f.y);y<Math.ceil(f.y+f.height);y++)for(let x=Math.floor(f.x);x<Math.ceil(f.x+f.width);x++)if(x>=0&&y>=0&&x<m.width&&y<m.height){covered.add(y*m.width+x);grid[y*m.width+x]=s.solid||s.kind==='water'?1:0;}o.collision={bounds:{x:s.x,y:s.y,width:s.width,height:f.height},height:s.height,standable:s.standable,solid:s.solid,kind:s.kind};}
// Distinguish vertical height from the rectangle's depth in the horizontal plane.

for(let y=0;y<m.height;y++)for(let x=0;x<m.width;x++){const k=y*m.width+x,g=m.layers.ground[k];if(['water','ocean','deep-water','lake','river'].includes(g)){surfaces.push({id:'water-'+k,x,y,width:1,depth:1,height:0,baseZ:0,kind:'water',solid:false,standable:false});grid[k]=1;}else if(m.layers.collision[k]&&!covered.has(k))surfaces.push({id:'wall-'+k,x,y,width:1,depth:1,height:99,baseZ:0,kind:'wall',solid:true,standable:false});}
m.layers.collision=grid;m.physics={version:1,units:'meters; 1 tile = 1 meter',player:{...DEFAULT},surfaces,annotationStatus:'rule-derived; compare against final artwork'};validate(m);return m;}
function validate(m){const p=m.physics;if(!p)return true;if(p.version!==1||!Array.isArray(p.surfaces)||p.surfaces.length>30000)throw Error('Invalid physics contract');const ids=new Set();for(const s of p.surfaces){if(typeof s.id!=='string'||ids.has(s.id))throw Error('Duplicate or missing collision ID');ids.add(s.id);if(![s.x,s.y,s.width,s.depth,s.height,s.baseZ].every(Number.isFinite)||s.width<=0||s.depth<=0||s.height<0||s.baseZ<0||s.x<0||s.y<0||s.x+s.width>m.width+EPS||s.y+s.depth>m.height+EPS||typeof s.solid!=='boolean'||typeof s.standable!=='boolean')throw Error('Invalid collision volume');}for(const [key,value]of Object.entries(DEFAULT))if(p.player?.[key]!==value)throw Error('Unsupported player physics parameters');return true;}
function intersects(s,x,y,r){const cx=Math.max(s.x,Math.min(x,s.x+s.width)),cy=Math.max(s.y,Math.min(y,s.y+s.depth));return (x-cx)**2+(y-cy)**2<r*r-EPS;}
function support(m,x,y){const r=DEFAULT.radius;if(x-r<0||y-r<0||x+r>m.width||y+r>m.height)return null;let z=0,platform=null;for(const s of m.physics.surfaces)if(s.standable&&intersects(s,x,y,r)&&s.baseZ+s.height>=z){z=s.baseZ+s.height;platform=s.id;}
for(const s of m.physics.surfaces)if(intersects(s,x,y,r)){if(s.kind==='water'&&z===0)return null;if(s.solid&&z<s.baseZ+s.height-EPS&&z+DEFAULT.bodyHeight>s.baseZ+EPS)return null;}return {z,platform};}
function clearAt(m,x,y,z){const r=DEFAULT.radius;if(x-r<0||y-r<0||x+r>m.width||y+r>m.height)return false;return !m.physics.surfaces.some(s=>s.solid&&intersects(s,x,y,r)&&z<s.baseZ+s.height-EPS&&z+DEFAULT.bodyHeight>s.baseZ+EPS);}
function jumpZ(base,end,t){const rise=end-base,H=DEFAULT.maxJumpRise,A=2*H-rise+2*Math.sqrt(H*(H-rise));return base+rise*t+A*t*(1-t);}
function attempt(m,from,to,mode='walk'){attach(m);if(!from||!to||![from.x,from.y,from.z??0,to.x,to.y].every(Number.isFinite)||!['walk','jump'].includes(mode))return {ok:false,reason:'无效的移动指令'};const dest=support(m,to.x,to.y);if(!dest)return {ok:false,reason:'目标没有可站立表面（树木、建筑或水域）'};const d=Math.hypot(to.x-from.x,to.y-from.y),base=from.z||0,end=dest.z;
if(mode==='jump'&&(d>DEFAULT.maxJumpDistance+EPS||end-base>DEFAULT.maxJumpRise+EPS))return {ok:false,reason:'超出跳跃距离或高度'};
if(mode==='walk'&&end-base>DEFAULT.stepHeight)return {ok:false,reason:'箱子或高台需要跳上去'};
let previousZ=base;const count=Math.max(2,Math.ceil(d/.06));for(let i=0;i<=count;i++){const t=i/count,x=from.x+(to.x-from.x)*t,y=from.y+(to.y-from.y)*t;let z=base+(end-base)*t;if(mode==='jump')z=jumpZ(base,end,t);else{const s=support(m,x,y);if(!s)return {ok:false,reason:'行走路线被障碍或水域阻挡'};if(s.z>previousZ+DEFAULT.stepHeight+EPS)return {ok:false,reason:'不能直接穿过高台'};z=s.z;previousZ=z;}
if(!clearAt(m,x,y,z))return {ok:false,reason:'身体碰撞到障碍，无法通过'};}
return {ok:true,player:{x:to.x,y:to.y,z:end,platform:dest.platform},distance:d};}
const api={DEFAULT,rule,attach,validate,support,clearAt,attempt,jumpZ};if(typeof module!=='undefined')module.exports=api;else root.MapPhysics=api;
})(typeof globalThis!=='undefined'?globalThis:this);


