from pathlib import Path
from lupa.lua53 import LuaRuntime
p=Path('scripts/modules/imported/prefab_2/d7508e1d-05a6-42d1-a7c8-5da9fd60d9b7.lua');s=p.read_text();l=LuaRuntime(unpack_returned_tuples=True)
l.execute('''
Vector3=setmetatable({up={x=0,y=1,z=0}},{__call=function(_,x,y,z)return{x=x,y=y,z=z}end})
Quaternion={LookRotation=function(v)return vNormalize(v)end}
function vSub(a,b)return Vector3(a.x-b.x,a.y-b.y,a.z-b.z)end
function vLength(v)return math.sqrt(v.x*v.x+v.y*v.y+v.z*v.z)end
function vNormalize(v)local n=vLength(v);return Vector3(v.x/n,v.y/n,v.z/n)end
function vDot(a,b)return a.x*b.x+a.y*b.y+a.z*b.z end
function clamp(x,a,b)return math.max(a,math.min(b,x))end
function isActorAlive()return true end
function equipActorInternal()return true end
function ensureTimelineScript()return{GetTimeline=function()return{duration=.5}end}end
function actorRoot(a)return a.root end
function setNodeActive()end;function setNodeScale()end
function tryBuildRig()end;function capturePose()end;function applyHoldingPose()end;function applyAttack()end
VALID_CLASSES={melee=true,ranged=true,mage=true};VALID_ATTACKS={attack=true,skill1=true,skill2=true,dash=true}
DEFAULT_ATTACK_KIND="attack";MAX_AIM_PITCH=1;AttackSpeed=1;Time={time=0};equippedByActor={}
''')
l.execute(s[s.index('local function faceAttack'):s.index('local function solveArm')]+'\nRunAttack=attackActorInternal;FaceAttack=faceAttack')
l.execute(s[s.index('function LateUpdate()'):s.index('function OnDisable()')].replace('faceAttack(', 'FaceAttack('))
l.execute('''
for _,class in ipairs({"melee","ranged","mage"})do
 for _,kind in ipairs({"attack","skill1","skill2","dash"})do
  local root={forward=Vector3(0,0,1),right=Vector3(1,0,0)}
  setmetatable(root,{__newindex=function(t,k,v)if k=="rotation"then t.forward=v;t.right=Vector3(v.z,0,-v.x)else rawset(t,k,v)end end})
  local actor={root=root,position=Vector3(0,0,0)}
  local entry={actor=actor,className=class};equippedByActor={[actor]=entry}
  assert(RunAttack(actor,class,kind,Vector3(0,0,-4)))
  if kind~="dash"then
   assert(root.forward.z<-.99 and math.abs(entry.attack.yawOffset)<.001,class..kind)
   root.rotation=Vector3(0,0,1) -- simulate native movement overwriting Update turn
   LateUpdate();assert(root.forward.z<-.99,'LateUpdate lost attack-facing priority')
  else assert(root.forward.z>.99 and entry.attack.facingWorld==nil,'dash heading changed')end
 end
end
''')
print('PASS 3 classes x 4 actions: turn before aim/pose; LateUpdate wins over movement; dash direction untouched')
