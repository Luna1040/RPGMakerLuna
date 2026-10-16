# 真的在干了 · v9

第一人称办公桌摸鱼原型。在拼豆、掌机横版跳跃和老板巡查之间安排时间，物品必须实际遮挡或藏入抽屉。

## 打开游戏

需要 Godot 4.7.2 标准版。首次下载建议运行 `python3 import_project.py`（可用 `--godot` 指定引擎），再导入本目录的 `project.godot`，打开 `main.tscn`，按 F5 运行。也可从 RPGMakerLuna 创作首页原《真的在干了》卡片进入。包内包含源码、运行素材和字体，不含引擎；普通试玩不需要团队连接服务。

使用 Git 获取仓库时先安装 Git LFS，并执行 `git lfs pull`。GitHub 源码自动 ZIP 可能只含大文件指针；本项目另提供完整源码素材 ZIP，配有 SHA256。

## 操作与目标

- 鼠标小幅环顾，中心稳定区；滚轮拉近/拉远。
- 左键查看物件、切换电脑页面、开关抽屉。近看时右键按住旋转、右键短按放回；Q 也可放回。
- 桌面右键拖动物件，绿色轮廓提示合法落点；松手平滑落稳，非法位置返回。
- 查看镊子后选择拿来拼豆，查看板子后点按钮或空格放豆，共 12 颗。
- 查看掌机后点屏幕：A/D 或方向键移动，空格跳跃，R 重试，Esc 离开屏幕。屏幕也提供鼠标按钮。
- 老板每次坐好后随机等 20–30 秒，起身后给 12 秒收拾。检查 4 秒，返回座位 10 秒，共三次。
- 用文件夹实际盖住拼豆板，把掌机与镊子放稳在抽屉内，关闭抽屉并切换工作页。前两次藏好即可继续；第三次到达前须完成 12 豆和掌机灯塔关卡，并藏好。
- 暂停、失焦不耗巡查时间。掌机藏起后保存关卡进度，取出后继续。

## v9 更新

右侧同事及对面老板工位；关节坐姿、起身绕椅与返回动作；物品细纹、釉面和金属质感；工位柔光；原创动漫静态单帧；办公室底噪、键盘与空间脚步。掌机与桌面统一时间，关卡固定 120Hz 子步，避免低帧率穿过危险。

## 验证与界限

发布副本验证见 `VALIDATION.json`，运行说明与实际图面/音频范围见 `TEST_REPORT.md`。人物仍是程序建模原型，默认输出 1280×800，不是16K CG成片。人工操作手感、实玩FPS及人工试听未认证；实际Metal隐藏渲染和Dummy混音路径已验证。退出时曾有7个Texture RID与2个ObjectDB资源清理警告。

```sh
python3 import_project.py --godot godot
godot --headless --path . --script res://tests/desk_input_test.gd
godot --headless --path . --script res://tests/desk_flow_test.gd
godot --headless --path . --script res://tests/desk_office_test.gd
godot --headless --path . --script res://tests/desk_platform_timing_test.gd
```

Godot首次加载全局中文字体早于素材冷导入，可能先输出一次字体缓存尚未生成的提示。`import_project.py`仅允许该已知首轮提示，完成字体导入后以原配置再次确认，第二次必须零错误；不修改项目设置。包内保留素材.import导入设置（包括纹理mipmap设置），不分发.godot机器缓存。

办公室投影与渲染benchmark测试写入Godot `user://`，无需作者本机的生成记录目录。其他可视采集测试运行时创建自己的诊断目录。素材来源见 `ASSET_PROVENANCE.md` 和 `SOURCE_GENERATION.json`；字体授权见 `FONT-LICENSE.txt`。
