from pathlib import Path
p=Path('created-games/velvet-mahogany/multiplayer.gd')
s=p.read_text(encoding='utf-8-sig')
s=s.replace('var npc_delay:=0.8','var npc_delay:=0.8\nvar board_visible_count:=0')
s=s.replace('var l:=Label.new()\n\tl.text=', 'var l:=Label.new()\n\tl.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART\n\tl.text=')
s=s.replace('for i in poker.board.size(): card(', 'for i in mini(board_visible_count,poker.board.size()): card(')
s=s.replace('if poker.board.is_empty(): label(', 'if board_visible_count==0: label(')
s=s.replace('busy=true; settled=false; selected=[]','busy=true; settled=false; selected=[]; board_visible_count=0')
s=s.replace('func drive_npcs() -> void:\n\tbusy=true\n\trefresh()', 'func drive_npcs() -> void:\n\tbusy=true\n\tawait reveal_board()\n\trefresh()')
s=s.replace('if mode=="holdem": poker.npc_move()\n\t\telse: ddz.npc_move()\n\t\trefresh()', 'if mode=="holdem": poker.npc_move()\n\t\telse: ddz.npc_move()\n\t\tawait reveal_board()\n\t\trefresh()')
s+='''\nfunc reveal_board() -> void:
	if mode!="holdem" or poker.board.size()<=board_visible_count: return
	message="薇拉正在发出公共牌……"
	refresh()
	await motion.begin("deal")
	board_visible_count=poker.board.size()
	refresh()
	await motion.complete()
'''
p.write_text(s,encoding='utf-8')
p=Path('created-games/velvet-mahogany/systems/holdem.gd')
s=p.read_text(encoding='utf-8-sig')
s=s.replace('messages.append("%s · %s"%[" / ".join(winners.map(func(i):return NAMES[i])),hand_name(best)])','messages.append("底池 %d → %s（%s）"%[pot," / ".join(winners.map(func(i):return NAMES[i])),hand_name(best)])')
p.write_text(s,encoding='utf-8')
