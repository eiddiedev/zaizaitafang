---@id e7e84f61-3127-4581-aa9e-e149619ec8cb
---@referenceName helpers_config.lua
---@assetRef eyJhc3NldElkIjoibWl4LWNyeXN0YWwtZGVmZW5zZTpoYW1sZXQtdWdjL2FpZ2NfZWRpdG9yL2Rldi91bml0eS9NUzR3TGpBQkFBQUFpWGVTbVJUZzVIekJKb1pRTkE0OEh1eXBoeWkxME4zNmk4QjJpenpZSjNZL21peC1wYXJ0LTBfX3VwbG9hZF9qeTQyZGQzeC5nbGIiLCJhc3NldFVyaSI6ImhhbWxldC11Z2MvYWlnY19lZGl0b3IvZGV2L3VuaXR5L01TNHdMakFCQUFBQWlYZVNtUlRnNUh6QkpvWlFOQTQ4SHV5cGh5aTEwTjM2aThCMml6ellKM1kvbWl4LXBhcnQtMF9fdXBsb2FkX2p5NDJkZDN4LmdsYiIsInJlZmVyZW5jZU5hbWUiOiJoZWxwZXJzX2NvbmZpZy5sdWEifQ
-- 晶界守卫的全部可调战斗配置。
---@displayName 战斗数值配置
local C = {version="0.1.0",core=20,startGold=360,prepare=45,intermission=15,voteTime=3,maxEnemies=90,maxPlayers=3}
C.themes={"forest"}
C.themeNames={forest="森林溪谷",snow="雪原要塞",desert="沙漠遗迹",night="幽夜古堡"}
C.themeDescriptions={forest="溪谷折返 · 桥头交叉火力",snow="堡垒长廊 · 贯穿与隘口",desert="遗迹分流 · 外圈汇合",night="月下庭院 · 双门侧路"}
C.names={crossbow="连弩塔",prism="棱晶塔",mortar="震爆炮台",slow="时缓信标",barrier="晶壁发生器",economy="辉晶采集器"}
C.branches={crossbow={"疾风连弩","猎标弩台"},prism={"贯星棱镜","蚀能晶塔"},mortar={"裂地重炮","余烬熔炉"},slow={"迟滞领域","禁锢矩阵"},barrier={"坚壁核心","反冲核心"},economy={"丰盈晶矿","共鸣回收站"}}
C.descriptions={crossbow="快速物理火力；重甲需魔法支援",prism="魔法伤害，忽略物理护甲",mortar="抛射范围攻击，快怪可走出落点",slow="减速与定身，为火力争取时间",barrier="临时晶壁阻挡，敌人可以击破",economy="团队唯一经济位；每波收益有上限"}
C.branchDescriptions={crossbow={"连续同目标射击越来越快","英雄触发猎标追加物理伤害"},prism={"直线贯穿3目标，后续伤害衰减","持续削减魔抗，第6击追加爆发"},mortar={"重击后原地余震","留下3秒燃烧区"},slow={"40%减速，离开后短暂残留","周期定身最多5只，Boss抗控"},barrier={"更高耐久与一次储备护盾","被击破时向后反冲普通怪"},economy={"稳定产出，清波额外奖励","附近击杀转化为额外收益"}}
local function tower(cost,damage,interval,range,extra)
  local t={cost=cost,damage=damage,interval=interval,range=range};for k,v in pairs(extra or {}) do t[k]=v end;return t
end
C.towers={
crossbow={tower(100,8,.40,8),tower(140,16,.38,8.5),tower(220,28,.34,9),a=tower(420,34,.25,9),b=tower(440,40,.32,9.5)},
prism={tower(140,26,.90,7.5),tower(180,52,.90,8),tower(260,94,.85,9),a=tower(440,132,.90,10.5),b=tower(460,122,.80,9)},
mortar={tower(150,70,2.8,9,{radius=2}),tower(180,125,2.8,9.5,{radius=2.2}),tower(280,240,2.6,10,{radius=2.4}),a=tower(470,340,2.8,10.5,{radius=2.6}),b=tower(490,260,2.5,10,{radius=2.5})},
slow={tower(110,4,1.2,5,{slow=.25}),tower(130,6,1.2,5.5,{slow=.30}),tower(210,8,1,6,{slow=.35}),a=tower(400,10,1,6.5,{slow=.4}),b=tower(430,8,1,6,{slow=.25})},
barrier={tower(100,0,12,5,{hp=600,capacity=3,duration=8}),tower(130,0,12,5,{hp=1100,capacity=4,duration=9}),tower(200,0,12,5,{hp=1800,capacity=5,duration=10}),a=tower(420,0,12,5,{hp=2500,capacity=6,duration=12}),b=tower(410,0,12,5,{hp=2000,capacity=5,duration=10})},
economy={tower(180,0,5,10,{income=4,cap=32}),tower(100,0,5,10,{income=6.5,cap=52}),tower(140,0,5,10,{income=9.5,cap=76}),a=tower(180,0,5,10,{income=13.5,cap=108}),b=tower(200,0,5,10,{income=6,cap=48})}
}
local function enemy(hp,armor,res,speed,damage,interval,threat,leak,extra)
 local e={hp=hp,armor=armor,res=res,speed=speed,damage=damage,interval=interval,threat=threat,leak=leak};for k,v in pairs(extra or {})do e[k]=v end;return e
end
C.enemies={basic=enemy(120,0,0,1.8,12,1,1,1),runner=enemy(90,0,0,2.8,8,.8,1.2,1),armored=enemy(360,80,0,1.2,22,1.5,3,2,{weight=2}),resistant=enemy(220,0,.45,1.5,16,1.2,2,1),ranged=enemy(180,10,0,1.6,24,2,2,1,{range=6,windup=.65}),healer=enemy(220,0,.15,1.4,0,4,2.5,1,{windup=.8}),breaker=enemy(320,30,0,1.3,28,1.4,3,2,{weight=2,windup=.75}),splitter=enemy(240,0,.1,1.5,16,1.2,2.5,2),child=enemy(55,0,0,2.2,6,.8,0,1),guard=enemy(1200,65,.1,1.1,50,2.4,8,3,{elite=true,weight=3,windup=1}),caster=enemy(1000,10,.35,1.3,40,1.6,8,3,{elite=true,range=7,windup=.8}),boss=enemy(10500,40,.2,.9,48,3.6,30,20,{boss=true,weight=99,range=5,windup=1.4})}
C.waves={
{basic=10,window=20},{basic=14,window=22},
{basic=10,runner=5,window=24},{basic=12,runner=9,window=25},
{basic=10,armored=3,window=26},{runner=10,armored=5,window=27},
{basic=12,resistant=5,window=27},{armored=5,resistant=7,runner=6,window=29},
{basic=12,ranged=5,window=28},{runner=12,ranged=7,armored=4,window=30},
{armored=6,healer=3,basic=12,window=30},{resistant=8,ranged=6,healer=3,window=32},
{basic=10,splitter=5,window=30},{runner=10,splitter=7,healer=3,window=32},
{armored=6,breaker=5,ranged=6,window=32},{breaker=8,resistant=8,healer=3,window=34},
{guard=1,armored=7,ranged=6,window=34},{guard=1,runner=12,splitter=6,window=35},
{caster=1,resistant=8,basic=12,window=34},{caster=1,breaker=6,healer=4,ranged=6,window=36},
{guard=2,runner=14,armored=8,window=37},{caster=2,splitter=8,healer=4,window=38},
{guard=1,caster=1,breaker=8,resistant=8,ranged=6,window=40},
{boss=1,basic=12,runner=8,healer=3,window=42}}
-- Authored endless encounters: separate from the 24-wave main campaign.
C.endlessWaves={
 [25]={basic=16,runner=10,armored=4,window=44},
 [26]={armored=8,ranged=8,healer=2,window=44},
 [27]={resistant=10,runner=12,splitter=5,window=44},
 [28]={guard=1,armored=8,ranged=6,window=44},
 [29]={caster=1,breaker=7,healer=2,runner=10,window=44},
 [30]={boss=1,basic=14,runner=8,healer=2,window=48},
 [31]={runner=18,splitter=8,ranged=6,window=46},
 [32]={armored=10,resistant=10,healer=3,window=46},
 [33]={breaker=9,ranged=10,runner=10,window=46},
 [34]={guard=2,armored=8,healer=2,window=46},
 [35]={caster=1,resistant=12,splitter=8,ranged=6,window=46},
 [36]={boss=1,armored=6,ranged=8,healer=2,window=50},
 [37]={armored=12,runner=14,healer=3,window=48},
 [38]={resistant=14,splitter=10,ranged=6,window=48},
 [39]={breaker=12,ranged=10,healer=3,window=48},
 [40]={guard=2,runner=16,splitter=7,window=48},
 [41]={caster=2,resistant=10,armored=8,healer=2,window=48},
 [42]={boss=1,runner=14,splitter=6,healer=2,window=52},
 [43]={runner=20,splitter=10,armored=8,window=50},
 [44]={resistant=16,ranged=12,healer=3,window=50},
 [45]={breaker=14,armored=10,runner=10,window=50},
 [46]={guard=2,armored=12,ranged=8,healer=3,window=50},
 [47]={caster=2,resistant=12,splitter=8,ranged=8,window=50},
 [48]={boss=1,breaker=8,ranged=8,healer=2,window=54},
 [49]={armored=14,resistant=14,runner=12,window=52},
 [50]={splitter=12,ranged=12,healer=4,window=52},
 [51]={breaker=14,runner=18,resistant=8,window=52},
 [52]={guard=3,armored=10,ranged=8,healer=3,window=52},
 [53]={caster=2,splitter=10,resistant=14,healer=3,window=52},
 [54]={boss=1,guard=1,runner=12,healer=2,window=56},
 [55]={runner=24,splitter=12,armored=10,window=54},
 [56]={armored=16,resistant=16,healer=4,window=54},
 [57]={breaker=16,ranged=14,runner=12,window=54},
 [58]={guard=3,armored=12,splitter=8,healer=3,window=54},
 [59]={guard=1,caster=2,resistant=14,ranged=10,healer=3,window=54},
 [60]={boss=1,caster=1,armored=8,runner=12,healer=2,window=58},
}
-- Linear interpolation keeps every wave continuous; bosses grow more gently.
C.endlessCurve={
 {wave=24,hp=3.07,bossHp=3.07,damage=2.38,bossDamage=2.38},
 {wave=30,hp=3.70,bossHp=3.45,damage=2.52,bossDamage=2.48},
 {wave=36,hp=4.45,bossHp=3.90,damage=2.68,bossDamage=2.60},
 {wave=42,hp=5.30,bossHp=4.40,damage=2.86,bossDamage=2.73},
 {wave=48,hp=6.25,bossHp=4.95,damage=3.06,bossDamage=2.87},
 {wave=54,hp=7.30,bossHp=5.55,damage=3.28,bossDamage=3.02},
 {wave=60,hp=8.45,bossHp=6.20,damage=3.52,bossDamage=3.18},
}
C.waveRewardBase=115;C.waveRewardStep=9;C.growthEvery=4
C.bestiary={
basic={name="裂隙魔物",asset="裂隙魔物·动画版",trait="普通近战 · 成群推进",detail="沿道路进攻水晶，靠近仔仔时会短暂停步攻击。",tip="连弩压制单体，炮塔清理密集怪群。"},
runner={name="裂隙疾爪",asset="裂隙疾爪·动画版",trait="高速突袭 · 不易拦截",detail="移动速度快，不会长时间与英雄缠斗。",tip="在弯道布置减速，让远程火力有时间输出。"},
armored={name="裂隙铁背",asset="裂隙铁背（动画版）",trait="重甲 · 物理减伤",detail="厚重甲壳抵挡大量物理伤害，推进较慢。",tip="棱晶塔和法师的魔法攻击更有效。"},
resistant={name="裂隙晶壳",asset="裂隙晶壳·动画守卫",trait="魔抗 · 晶壳防护",detail="晶体外壳削减魔法伤害。",tip="使用连弩、炮塔和剑士的物理攻击。"},
ranged={name="裂隙投矛手",asset="裂隙投矛手（动画版）",trait="远程投射 · 锁定落点",detail="蓄力后向仔仔所在位置投射。攻击距离有限。",tip="看到蓄力和落点提示后横向移动，弹药不会追踪。"},
healer={name="裂隙灯祭者",asset="灯祭者（动作版）",trait="群体治疗 · 后排支援",detail="周期性治疗附近魔物，让怪群更难清理。",tip="优先切入击杀，避免只攻击被持续治疗的重甲。"},
splitter={name="裂隙裂团",asset="裂隙裂团（动画版）",trait="死亡分裂 · 二次进攻",detail="被击败后分裂成两只快速子体。",tip="保留范围技能，在分裂后一起清除。"},
child={name="裂团子体",asset="裂团子体·动画版",trait="轻型快怪 · 来自分裂",detail="裂团死亡后出现。生命少、速度快，仍可伤害水晶。",tip="用炮塔或范围技能及时收尾。"},
breaker={name="裂隙破门兽",asset="破门兽（骨骼动画版）",trait="重击 · 破坏晶壁",detail="优先冲击阻挡它的晶壁，重击前有蓄力。",tip="利用蓄力间隙闪避，集中火力消灭。"},
guard={name="裂隙铁卫统领",asset="裂隙铁卫统领（动画版）",trait="精英重甲 · 强力近战",detail="高生命和护甲，控制效果持续时间缩短。",tip="魔法火力配合减速，不要长时间站在近战范围。"},
caster={name="裂隙蚀光使",asset="裂隙蚀光使（动画版）",trait="精英法术 · 落点轰击",detail="在有限距离内蓄力施法，攻击锁定的地面区域。",tip="看到提示立即离开落点，保持横向移动。"},
boss={name="界门巨兽",asset="界门巨兽（骨骼动画版）",trait="最终首领 · 阶段重击",detail="高生命，随生命降低改变攻击节奏。仅威胁附近目标。",tip="观察蓄力落点，输出后撤离；避免贴身连续承受重击。"}}
C.introductions={};local known={}
for wave,entry in ipairs(C.waves)do
 local list={};for _,kind in ipairs({"basic","runner","armored","resistant","ranged","healer","splitter","child","breaker","guard","caster","boss"})do
  if (entry[kind]or(kind=="child"and entry.splitter))and not known[kind]then known[kind]=true;list[#list+1]=kind end
 end;C.introductions[wave]=list
end
C.hero={melee={hp=640,armor=20,speed=2.9,damage=28,interval=.65,range=1.7,skill1=60,skill2=7},ranged={hp=480,armor=10,speed=3.1,damage=22,interval=.45,range=9,skill1=70,skill2=8}}
C.hero.mage={hp=440,armor=5,speed=2.9,damage=34,interval=.85,range=9,skill1=75,skill2=9}
C.countScale={1,1.35,1.65,1.9};C.healthScale={1,1.2,1.35,1.5};C.eliteScale={1,1.6,2.2,2.8}
function GetConfig() return C end
function TowerStats(kind,tier,branch) local t=C.towers[kind];return t and t[tier==4 and branch or tier] end