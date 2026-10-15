extends RefCounted
class_name GameData

const COCKTAIL := [
	{
		"id": "base",
		"title": "基酒",
		"options": [
			{"id":"still_sea", "name":"静海", "desc":"最大生命 +20%", "color":"4cc9d8", "quality":"普通", "cost":0},
			{"id":"reverse_fire", "name":"逆火", "desc":"普通攻击 +15%", "color":"d84c63", "quality":"稀有", "cost":120}
		]
	},
	{
		"id": "emotion",
		"title": "情绪剂",
		"options": [
			{"id":"empathy", "name":"共情", "desc":"显示隐藏叙事线索", "color":"65c6a4", "quality":"普通", "cost":0},
			{"id":"anger", "name":"愤怒", "desc":"增加敌人，报酬 +15%", "color":"e45a3f", "quality":"稀有", "cost":140}
		]
	},
	{
		"id": "catalyst",
		"title": "催化剂",
		"options": [
			{"id":"stable", "name":"稳定", "desc":"悖论增长 ×0.7", "color":"e7b95a", "quality":"普通", "cost":0},
			{"id":"overload", "name":"过载", "desc":"稀有线索提前显现，初始悖论 +20", "color":"bd5ce0", "quality":"史诗", "cost":220}
		]
	}
]

static func all_drinks() -> Array[Dictionary]:
	var drinks: Array[Dictionary] = []
	for group in COCKTAIL:
		for option in group.options:
			var drink: Dictionary = option.duplicate()
			drink["category"] = group.title
			drinks.append(drink)
	return drinks

static func drink_by_id(id: String) -> Dictionary:
	for drink in all_drinks():
		if drink.id == id: return drink
	return {}

const DIALOGUE := {
	"arrival": {
		"speaker":"周骁",
		"text":"十二年前，雾港七号街。我朝黎雾开了一枪。她死了——至少企业是这么告诉我的。",
		"options":[{"text":"继续。", "next":"request"}]
	},
	"request": {
		"speaker":"周骁",
		"text":"让我回去。让我没有扣下扳机。价钱不是问题，我只要昨夜不存在。",
		"options":[
			{"text":"你记得弹道吗？", "next":"trajectory", "flag":"trajectory"},
			{"text":"你亲眼看见尸体了吗？", "next":"body", "flag":"body"},
			{"text":"企业为什么允许你离开？", "next":"corporate", "flag":"corporate"}
		]
	},
	"trajectory": {
		"speaker":"周骁",
		"text":"枪口朝东，尸体却倒在北侧。你看，我甚至连自己的记忆都无法作证。",
		"options":[{"text":"这就是我们要找的裂缝。", "next":"warning"}]
	},
	"body": {
		"speaker":"周骁",
		"text":"没有。医疗员挡住了我。担架上的人盖着银色隔离膜，没有死亡确认。",
		"options":[{"text":"那就先找医疗员的视角。", "next":"warning"}]
	},
	"corporate": {
		"speaker":"周骁",
		"text":"他们说忠诚比真相重要。第二天我升职，档案里再也没有黎雾这个人。",
		"options":[{"text":"升职是封口费。", "next":"warning"}]
	},
	"warning": {
		"speaker":"玩家",
		"text":"我能改写因果锚点，不能替你制造清白。记忆会反抗，现实也会收取差价。",
		"options":[{"text":"接受委托。", "next":"accepted"}]
	},
	"accepted": {
		"speaker":"周骁",
		"text":"酒里不要放让我遗忘的东西。我要记住真相——哪怕它不是我想要的。",
		"options":[{"text":"去吧台调制神经鸡尾酒。", "next":"END"}]
	}
}

const ROOMS := [
	{
		"id":"street",
		"name":"表层记忆 / 七号街雨夜",
		"objective":"清除防卫程序，固定‘一声枪响’",
		"clue":"子弹轨迹与倒地位置矛盾",
		"theme":"street",
		"enemies":[
			{"type":"melee", "pos":Vector2(205,78)},
			{"type":"shooter", "pos":Vector2(255,125)},
			{"type":"noise", "pos":Vector2(160,60)}
		]
	},
	{
		"id":"station",
		"name":"隐藏记忆 / 企业医疗站",
		"objective":"击败医疗员见证者并按 E 借身",
		"clue":"黎雾在枪击后仍有生命体征",
		"theme":"station",
		"enemies":[
			{"type":"melee", "pos":Vector2(190,62)},
			{"type":"noise", "pos":Vector2(225,130)},
			{"type":"witness", "pos":Vector2(264,88)}
		]
	},
	{
		"id":"root",
		"name":"根层记忆 / 神经实验室",
		"objective":"击败校正者，接触因果锚点",
		"clue":"黎雾主动让自己从公共记录中死亡",
		"theme":"root",
		"enemies":[{"type":"boss", "pos":Vector2(235,88)}]
	}
]

const CHARACTERS := {
	"melee":{"name":"近战防卫", "hp":54.0, "speed":34.0, "damage":10.0, "color":"df6b54"},
	"shooter":{"name":"射手程序", "hp":42.0, "speed":22.0, "damage":8.0, "color":"d957a8"},
	"noise":{"name":"记忆噪点", "hp":36.0, "speed":25.0, "damage":7.0, "color":"8567d6"},
	"witness":{"name":"企业医疗员", "hp":120.0, "speed":20.0, "damage":9.0, "color":"62d7bc"},
	"boss":{"name":"校正者", "hp":360.0, "speed":25.0, "damage":12.0, "color":"f04b55"}
}

const UPGRADES := [
	{"id":"pulse", "name":"脉冲弹", "desc":"每第 3 次命中释放连锁电流"},
	{"id":"second_dash", "name":"二次脉搏", "desc":"冲刺可储存 2 次"},
	{"id":"shield", "name":"反馈屏障", "desc":"冲刺后获得 1 层护盾"},
	{"id":"drain", "name":"记忆汲取", "desc":"击败敌人恢复 8 生命"},
	{"id":"overclock", "name":"过钟频率", "desc":"Q 冷却 -25%，悖论 +10"},
	{"id":"copy", "name":"错误复制", "desc":"每第 4 次攻击追加延迟射击"}
]

const ENDINGS := {
	"shot_prevented": {
		"name":"阻止开枪",
		"choice":"截断扳机信号，让枪声从未发生",
		"bar":"神经服务器消失；周骁成为企业安保主管",
		"paradox":15.0,
		"alignment":25
	},
	"shot_preserved": {
		"name":"维持枪击",
		"choice":"保留枪声，把真相交还给周骁",
		"bar":"酒吧保持原样；周骁终于知道自己没有杀人",
		"paradox":0.0,
		"alignment":18
	},
	"death_faked": {
		"name":"伪造假死",
		"choice":"改写现场记录，让黎雾提前逃离",
		"bar":"墙上出现你与黎雾的合照；一通来电正在等待",
		"paradox":30.0,
		"alignment":12
	}
}
