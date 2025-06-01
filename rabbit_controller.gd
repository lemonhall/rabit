extends Node2D

# 引用AnimatedSprite2D节点
@onready var animated_sprite = $AnimatedSprite2D

# 动画状态枚举
enum AnimationState {
	IDLE,
	WALK,
	COOLDOWN,  # 冷却状态，短暂不能移动
	KICK       # 踢腿状态
}

# 移动参数
@export var move_speed: float = 200.0
@export var min_walk_time: float = 1.0  # 最小连续移动时间
@export var max_walk_time: float = 2.0  # 最大连续移动时间
@export var cooldown_time: float = 0.8   # 冷却时间

# 当前动画状态
var current_state = AnimationState.IDLE
var is_moving = false
var facing_right = true  # 记录角色朝向，true为右，false为左
var walk_timer = 0.0     # 移动计时器
var cooldown_timer = 0.0 # 冷却计时器
var current_walk_limit = 0.0  # 当前这次移动的时间限制

func _ready():
	# 确保开始时播放idle动画，朝向右边
	animated_sprite.play("idle")
	animated_sprite.flip_h = false  # 确保开始时不翻转（朝右）
	current_state = AnimationState.IDLE
	facing_right = true
	
	# 连接动画完成信号
	animated_sprite.animation_finished.connect(_on_animation_finished)

func _process(delta):
	# 更新计时器
	update_timers(delta)
	
	# 检测输入来控制移动和动作
	handle_input(delta)
	
	# 根据移动状态更新动画
	update_animation()

func generate_random_walk_time() -> float:
	"""生成随机的移动时间限制"""
	return randf_range(min_walk_time, max_walk_time)

func update_timers(delta):
	"""更新各种计时器"""
	if current_state == AnimationState.WALK:
		walk_timer += delta
		
		# 如果移动时间超过当前限制，强制进入冷却
		if walk_timer >= current_walk_limit:
			print("移动时间到达上限(%.1f秒)，强制休息！" % current_walk_limit)
			start_cooldown()
	
	elif current_state == AnimationState.COOLDOWN:
		cooldown_timer += delta
		
		# 冷却时间结束，可以重新移动
		if cooldown_timer >= cooldown_time:
			current_state = AnimationState.IDLE
			animated_sprite.play("idle")
			print("休息完毕，可以继续移动了！")

func handle_input(delta):
	# 检测kick输入（Z键）
	if Input.is_action_just_pressed("ui_accept") or Input.is_key_pressed(KEY_Z):
		if can_perform_action():
			perform_kick()
			return  # kick时不处理移动
	
	# 检测水平移动输入
	var horizontal_input = 0.0
	
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		horizontal_input += 1.0
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		horizontal_input -= 1.0
	
	# 只有在非冷却和非kick状态下才能移动
	if current_state != AnimationState.COOLDOWN and current_state != AnimationState.KICK:
		# 更新移动状态
		is_moving = abs(horizontal_input) > 0
		
		# 实际移动角色（只处理水平移动）
		if is_moving:
			var movement = horizontal_input * move_speed * delta
			position.x += movement
			
			# 更新角色朝向
			update_facing_direction(horizontal_input)
	else:
		# 冷却期间或kick期间不能移动
		is_moving = false

func can_perform_action() -> bool:
	"""检查是否可以执行动作（kick等）"""
	return current_state == AnimationState.IDLE or current_state == AnimationState.WALK

func perform_kick():
	"""执行kick动作"""
	print("兔子踢腿！朝向:", "右" if facing_right else "左")
	current_state = AnimationState.KICK
	animated_sprite.play("kick")
	is_moving = false  # kick时停止移动
	walk_timer = 0.0   # 重置移动计时器

func update_facing_direction(horizontal_input: float):
	"""根据移动方向更新角色朝向"""
	if horizontal_input > 0:
		# 向右移动
		facing_right = true
		animated_sprite.flip_h = false
	elif horizontal_input < 0:
		# 向左移动
		facing_right = false
		animated_sprite.flip_h = true

func update_animation():
	"""动画更新逻辑"""
	if current_state == AnimationState.COOLDOWN or current_state == AnimationState.KICK:
		# 冷却期间或kick期间不更新动画
		return
	
	if is_moving and current_state != AnimationState.WALK:
		# 开始移动，切换到walk
		current_state = AnimationState.WALK
		animated_sprite.play("walk")
		walk_timer = 0.0  # 重置移动计时器
		current_walk_limit = generate_random_walk_time()  # 生成新的随机时间限制
		print("开始移动，本次移动时间限制: %.1f秒" % current_walk_limit)
	elif not is_moving and current_state != AnimationState.IDLE:
		# 停止移动，直接切换到idle
		current_state = AnimationState.IDLE
		animated_sprite.play("idle")
		walk_timer = 0.0  # 重置移动计时器

func start_cooldown():
	"""开始冷却期"""
	current_state = AnimationState.COOLDOWN
	animated_sprite.play("idle")
	walk_timer = 0.0
	cooldown_timer = 0.0
	is_moving = false

func _on_animation_finished():
	"""当动画播放完成时调用"""
	if current_state == AnimationState.KICK:
		# kick动画完成，返回idle状态
		current_state = AnimationState.IDLE
		animated_sprite.play("idle")
		print("踢腿完成，回到待机状态")
	elif current_state == AnimationState.WALK and is_moving:
		# walk动画播放完成，如果还在移动且未超时，重新播放walk动画
		if walk_timer < current_walk_limit:
			animated_sprite.play("walk")
		else:
			# 时间到了，强制休息
			start_cooldown()
	elif current_state == AnimationState.IDLE or current_state == AnimationState.COOLDOWN:
		# idle动画完成，继续播放idle
		animated_sprite.play("idle")

# 调试信息
func _input(event):
	if event.is_action_pressed("ui_select"):  # 空格键（改为ui_select避免与kick冲突）
		print("=== 兔子状态调试信息 ===")
		print("当前状态: ", AnimationState.keys()[current_state])
		print("是否移动: ", is_moving)
		print("位置: ", position)
		print("朝向右边: ", facing_right)
		print("精灵翻转: ", animated_sprite.flip_h)
		print("移动计时器: ", "%.2f" % walk_timer, "/", "%.1f" % current_walk_limit)
		print("冷却计时器: ", "%.2f" % cooldown_timer, "/", cooldown_time)
		print("当前动画: ", animated_sprite.animation)

# 边界检查
func _physics_process(_delta):
	# 获取视口大小
	var viewport_size = get_viewport().get_visible_rect().size
	
	# 限制角色在屏幕范围内（主要是水平边界）
	position.x = clamp(position.x, 50, viewport_size.x - 50)

# 跳跃功能（预留）
func jump():
	"""跳跃功能（可以扩展）"""
	if can_perform_action():
		print("兔子跳跃！")
	else:
		print("当前状态无法跳跃！")

# 跳跃输入检测
func _unhandled_input(event):
	if event.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		jump() 
