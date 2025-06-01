extends Node2D

# 引用AnimatedSprite2D节点
@onready var animated_sprite = $AnimatedSprite2D

# 动画状态枚举
enum AnimationState {
	IDLE,
	WALK,
	COOLDOWN,  # 冷却状态，短暂不能移动
	KICK,      # 踢腿状态
	JUMP,      # 跳跃状态
	DUCK_DOWN, # 下蹲过程
	DUCK_HOLD, # 保持蹲下状态
	TURN_SHOT, # 转换到射击状态
	SHOOTING   # 持续射击状态
}

# 移动参数
@export var move_speed: float = 300.0
@export var min_walk_time: float = 1.0  # 最小连续移动时间
@export var max_walk_time: float = 2.0  # 最大连续移动时间
@export var cooldown_time: float = 0.5   # 冷却时间

# 跳跃物理参数
@export var jump_force: float = -1200.0   # 跳跃初始速度（负数向上）
@export var gravity: float = 2200.0       # 重力加速度
@export var ground_y: float = 0.0        # 地面Y坐标（会在_ready中设置）

# 当前动画状态
var current_state = AnimationState.IDLE
var is_moving = false
var facing_right = true  # 记录角色朝向，true为右，false为左
var walk_timer = 0.0     # 移动计时器
var cooldown_timer = 0.0 # 冷却计时器
var current_walk_limit = 0.0  # 当前这次移动的时间限制

# 跳跃物理状态
var velocity_y: float = 0.0  # 垂直速度
var is_on_ground: bool = true  # 是否在地面上

# duck保持状态的变量
var duck_hold_timer: float = 0.0  # duck保持状态的计时器
var duck_hold_frame_duration: float = 0.1  # 每帧持续时间
var duck_total_frames: int = 0  # duck动画总帧数
var duck_hold_start_frame: int = 0  # 保持状态开始的帧数（总帧数-20）

func _ready():
	# 确保开始时播放idle动画，朝向右边
	animated_sprite.play("idle")
	animated_sprite.flip_h = false  # 确保开始时不翻转（朝右）
	current_state = AnimationState.IDLE
	facing_right = true
	
	# 设置地面Y坐标为当前位置
	ground_y = position.y
	
	# 初始化duck动画相关变量
	duck_total_frames = animated_sprite.sprite_frames.get_frame_count("duck")
	duck_hold_start_frame = max(0, duck_total_frames - 20)  # 最后20帧，如果不足20帧则从0开始
	print("Duck动画总帧数: ", duck_total_frames, ", 保持状态从第", duck_hold_start_frame, "帧开始")
	
	# 连接动画完成信号
	animated_sprite.animation_finished.connect(_on_animation_finished)

func _process(delta):
	# 更新计时器
	update_timers(delta)
	
	# 更新跳跃物理
	update_jump_physics(delta)
	
	# 更新duck保持状态
	update_duck_hold(delta)
	
	# 检测输入来控制移动和动作
	handle_input(delta)
	
	# 根据移动状态更新动画
	update_animation()

func update_jump_physics(delta):
	"""更新跳跃物理效果"""
	if current_state == AnimationState.JUMP:
		# 应用重力
		velocity_y += gravity * delta
		
		# 更新垂直位置
		position.y += velocity_y * delta
		
		# 检查是否落地
		if position.y >= ground_y:
			position.y = ground_y
			velocity_y = 0.0
			is_on_ground = true
			
			# 跳跃结束，返回idle状态
			current_state = AnimationState.IDLE
			animated_sprite.play("idle")
			print("跳跃落地，回到待机状态")
	else:
		# 确保在地面上
		if position.y > ground_y:
			position.y = ground_y
		is_on_ground = true

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
	# 检测射击输入（鼠标左键）- 检测按住状态
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if can_perform_action():
			perform_shoot()
			return  # 射击时不处理其他输入
	else:
		# 如果松开了射击键，且当前在射击状态，则回到idle
		if current_state == AnimationState.TURN_SHOT or current_state == AnimationState.SHOOTING:
			current_state = AnimationState.IDLE
			animated_sprite.play("idle")
			print("停止射击，回到待机状态")
			return
	
	# 检测jump输入（W键或上箭头）- 只有在地面上才能跳跃
	if (Input.is_action_just_pressed("ui_up") or Input.is_key_pressed(KEY_W)) and is_on_ground:
		if can_perform_action():
			perform_jump()
			return  # jump时不处理其他输入
	
	# 检测duck输入（S键或下箭头）- 检测按住状态
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		if can_perform_action():
			perform_duck()
			return  # duck时不处理其他输入
	else:
		# 如果松开了duck键，且当前在duck状态，则回到idle
		if current_state == AnimationState.DUCK_DOWN or current_state == AnimationState.DUCK_HOLD:
			current_state = AnimationState.IDLE
			animated_sprite.play("idle")
			duck_hold_timer = 0.0  # 重置计时器
			print("松开蹲下键，回到待机状态")
			return
	
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
	
	# 只有在非冷却、非kick、非duck、非射击状态下才能移动（跳跃时可以移动）
	if current_state != AnimationState.COOLDOWN and current_state != AnimationState.KICK and current_state != AnimationState.DUCK_DOWN and current_state != AnimationState.DUCK_HOLD and current_state != AnimationState.TURN_SHOT and current_state != AnimationState.SHOOTING:
		# 更新移动状态
		is_moving = abs(horizontal_input) > 0
		
		# 实际移动角色（只处理水平移动）
		if is_moving:
			var movement = horizontal_input * move_speed * delta
			position.x += movement
			
			# 更新角色朝向（跳跃时也可以改变朝向）
			update_facing_direction(horizontal_input)
	else:
		# 冷却期间、kick期间、duck期间或射击期间不能移动
		is_moving = false

func can_perform_action() -> bool:
	"""检查是否可以执行动作（kick、jump等）"""
	return current_state == AnimationState.IDLE or current_state == AnimationState.WALK

func perform_jump():
	"""执行jump动作"""
	print("兔子跳跃！朝向:", "右" if facing_right else "左")
	current_state = AnimationState.JUMP
	animated_sprite.play("jump")
	
	# 设置跳跃物理参数
	velocity_y = jump_force  # 给予向上的初始速度
	is_on_ground = false
	
	is_moving = false  # jump时停止水平移动状态更新
	walk_timer = 0.0   # 重置移动计时器

func perform_kick():
	"""执行kick动作"""
	print("兔子踢腿！朝向:", "右" if facing_right else "左")
	current_state = AnimationState.KICK
	animated_sprite.play("kick")
	is_moving = false  # kick时停止移动
	walk_timer = 0.0   # 重置移动计时器

func perform_duck():
	"""执行duck动作"""
	# 只有在非duck状态时才开始duck
	if current_state != AnimationState.DUCK_DOWN and current_state != AnimationState.DUCK_HOLD:
		print("兔子蹲下！朝向:", "右" if facing_right else "左")
		current_state = AnimationState.DUCK_DOWN
		animated_sprite.play("duck")
		is_moving = false  # duck时停止移动
		walk_timer = 0.0   # 重置移动计时器

func perform_shoot():
	"""执行射击动作"""
	# 只有在非射击状态时才开始射击
	if current_state != AnimationState.TURN_SHOT and current_state != AnimationState.SHOOTING:
		print("兔子开始射击！朝向:", "右" if facing_right else "左")
		current_state = AnimationState.TURN_SHOT
		animated_sprite.play("turn_shot")
		is_moving = false  # 射击时停止移动
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
	if current_state == AnimationState.COOLDOWN or current_state == AnimationState.KICK or current_state == AnimationState.JUMP or current_state == AnimationState.DUCK_DOWN or current_state == AnimationState.DUCK_HOLD or current_state == AnimationState.TURN_SHOT or current_state == AnimationState.SHOOTING:
		# 冷却期间、kick期间、jump期间、duck期间或射击期间不更新行走动画
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
	if current_state == AnimationState.JUMP:
		# jump动画完成，但物理效果可能还在继续
		# 实际的跳跃结束由物理系统控制（落地时）
		print("跳跃动画播放完成")
	elif current_state == AnimationState.KICK:
		# kick动画完成，返回idle状态
		current_state = AnimationState.IDLE
		animated_sprite.play("idle")
		print("踢腿完成，回到待机状态")
	elif current_state == AnimationState.TURN_SHOT:
		# turn_shot动画完成，进入持续射击状态
		current_state = AnimationState.SHOOTING
		animated_sprite.play("shoting")
		print("转换完成，进入持续射击状态")
	elif current_state == AnimationState.SHOOTING:
		# shoting动画完成，继续循环播放（如果还在按住射击键）
		# 这个状态的结束由输入检测控制，这里只是确保循环
		animated_sprite.play("shoting")
	elif current_state == AnimationState.DUCK_DOWN:
		# duck动画完成，进入保持状态
		current_state = AnimationState.DUCK_HOLD
		# 暂停动画，准备手动控制帧
		animated_sprite.pause()
		animated_sprite.frame = duck_hold_start_frame
		duck_hold_timer = 0.0
		print("蹲下完成，进入保持状态")
	elif current_state == AnimationState.DUCK_HOLD:
		# duck_hold状态下不应该触发animation_finished，因为我们手动控制帧
		pass
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
		print("垂直速度: ", "%.2f" % velocity_y)
		print("在地面上: ", is_on_ground)
		print("地面Y坐标: ", ground_y)

# 边界检查
func _physics_process(_delta):
	# 获取视口大小
	var viewport_size = get_viewport().get_visible_rect().size
	
	# 限制角色在屏幕范围内（主要是水平边界）
	position.x = clamp(position.x, 50, viewport_size.x - 50)

# 跳跃功能（现在已经实现）
func jump():
	"""跳跃功能（已实现为perform_jump）"""
	if is_on_ground:
		perform_jump()
	else:
		print("在空中，无法跳跃！")

# 移除原来的跳跃输入检测，现在在handle_input中处理 

func update_duck_hold(delta):
	"""更新duck保持状态的帧循环"""
	if current_state == AnimationState.DUCK_HOLD:
		duck_hold_timer += delta
		
		# 每隔一定时间切换帧
		if duck_hold_timer >= duck_hold_frame_duration:
			duck_hold_timer = 0.0
			
			# 获取当前帧
			var current_frame = animated_sprite.frame
			
			# 如果当前帧小于保持状态开始帧，设置到开始帧
			if current_frame < duck_hold_start_frame:
				animated_sprite.frame = duck_hold_start_frame
			else:
				# 在最后20帧之间循环
				current_frame += 1
				if current_frame >= duck_total_frames:
					current_frame = duck_hold_start_frame
				animated_sprite.frame = current_frame

# 移除原来的跳跃输入检测，现在在handle_input中处理 
