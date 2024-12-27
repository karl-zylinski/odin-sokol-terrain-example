// SOKOL example that has loads and displays a heightmap (heightmap.png). There
// is also a free-fly camera (hold right mouse button to rotate camera).

package game

import "base:runtime"
import slog "sokol/log"
import sg "sokol/gfx"
import sapp "sokol/app"
import sglue "sokol/glue"
import sshape "sokol/shape"

import "core:math/linalg"
import "core:os"
import "core:c"

import stbi "vendor:stb/image"

state: struct {
	pip: sg.Pipeline,
	bind: sg.Bindings,
	pass_action: sg.Pass_Action,
}

Vertex :: struct {
	x, y, z: f32,
	u, v: u16,
}

default_context: runtime.Context

init :: proc "c" () {
	context = default_context
	pos = {0, 5, -6}

	sg.setup({
		environment = sglue.environment(),
		logger = { func = slog.func },
	})

	vertices := make([]sshape.Vertex, 6*100*100)
	indices := make([]u16, 16*100*100)
	buf := sshape.Buffer {
        vertices = { buffer = { ptr = raw_data(vertices), size = u64(len(vertices) * size_of(Vertex)) } },
        indices  = { buffer = { ptr = raw_data(indices), size = u64(len(indices) * size_of(u16)) } },
    }

 	buf = sshape.build_plane(buf, {
        width = 100.0,
        depth = 100.0,
        tiles = 100,
        random_colors = true,
    })

	state.bind.vertex_buffers[0] = sg.make_buffer(sshape.vertex_buffer_desc(buf))

	state.bind.index_buffer = sg.make_buffer(sshape.index_buffer_desc(buf))

	if heightmap_data, heightmap_data_ok := os.read_entire_file("heightmap.png"); heightmap_data_ok {
		sx, sy: c.int
		img := stbi.load_from_memory(raw_data(heightmap_data), i32(len(heightmap_data)), &sx, &sy, nil, 1)

	  	state.bind.vs.images[SLOT_tex] = sg.make_image({
			width = c.int(sx),
			height = c.int(sy),
			pixel_format = .R8,
			data = {
				subimage = {
					0 = {
						0 = { ptr = img, size = u64(sx * sy) },
					},
				},
			},
		})
	}


	// a sampler with default options to sample the above image as texture
	state.bind.vs.samplers[SLOT_smp] = sg.make_sampler({ wrap_u = .CLAMP_TO_EDGE, wrap_v = .CLAMP_TO_EDGE})

	// create a shader and pipeline object (default render states are fine for triangle)
	state.pip = sg.make_pipeline({
		shader = sg.make_shader(cube_shader_desc(sg.query_backend())),
		layout = {
			attrs = {
                ATTR_vs_position = sshape.position_vertex_attr_state(),
                ATTR_vs_normal   = sshape.normal_vertex_attr_state(),
                ATTR_vs_texcoord = sshape.texcoord_vertex_attr_state(),
                ATTR_vs_color0   = sshape.color_vertex_attr_state(),
			},
		},
		index_type = .UINT16,
		cull_mode = .BACK,
		depth = {
			write_enabled = true,
			compare = .LESS_EQUAL,
		},
	})

	// a pass action to clear framebuffer to black
	state.pass_action = {
		colors = {
			0 = { load_action = .CLEAR, clear_value = { 0.2, 0.4, 0.6, 1.0 } },
		},
	}
}

pos: Vec3

frame :: proc "c" () {
	context = default_context

	sg.begin_pass({ action = state.pass_action, swapchain = sglue.swapchain() })
	sg.apply_pipeline(state.pip)
	sg.apply_bindings(state.bind)

	time += sapp.frame_duration()
	t := f32(sapp.frame_duration())

	movement: Vec3

	if key_held[.Forward] {
		movement.z += 1
	}

	if key_held[.Backward] {
		movement.z -= 1
	}

	if key_held[.Left] {
		movement.x += 1
	}

	if key_held[.Right] {
		movement.x -= 1
	}

	rot := linalg.matrix4_from_yaw_pitch_roll_f32(yaw, pitch, 0)
	pos += linalg.mul(rot, vec4_point(linalg.normalize0(movement)*t*50)).xyz

	vs_params := Vs_Params {
		mvp = compute_view_proj(),
		time = f32(time),
	}

	if mouse_held[.Right] {
		yaw -= mouse_move.x * t * 0.3
		pitch += mouse_move.y * t * 0.3

		if !sapp.mouse_locked() {
			sapp.lock_mouse(true)
		}
	} else {
		if sapp.mouse_locked() {
			sapp.lock_mouse(false)
		}
	}

	sg.apply_uniforms(.VS, SLOT_vs_params, { ptr = &vs_params, size = size_of(vs_params)} )
	sg.draw(0, 100000, 1)
	sg.end_pass()
	sg.commit()
	mouse_move = {}
}

vec4_point :: proc(v: Vec3) -> Vec4 {
	return {v.x, v.y, v.z, 1}
}

Vec3 :: [3]f32
Vec4 :: [4]f32
Mat4 :: matrix[4,4]f32
time: f64

yaw: f32
pitch: f32

compute_view_proj :: proc () -> Mat4 {
	proj := linalg.matrix4_perspective(60 * (3.14/180), sapp.widthf() / sapp.heightf(), 0.01, 1000)
	rot := linalg.matrix4_from_yaw_pitch_roll_f32(yaw, pitch, 0)
	look := pos + linalg.mul(rot, Vec4{0, 0, -1, 1}).xyz
	view := linalg.matrix4_look_at(look, pos, Vec3{0.0, 1.0, 0.0})
	view_proj := proj * view
	return view_proj
}

cleanup :: proc "c" () {
	context = default_context
	sg.shutdown()
}

Key :: enum {
	Forward,
	Backward,
	Left,
	Right,
}

key_held: [Key]bool

Mouse_Button :: enum {
	Left,
	Right,
}

mouse_held: [Mouse_Button]bool
mouse_move: [2]f32

event :: proc "c" (e: ^sapp.Event) {
	context = default_context

	#partial switch e.type {
		case .MOUSE_MOVE: 
			mouse_move += {e.mouse_dx, e.mouse_dy}

		case .KEY_DOWN:
			if e.key_code == .W {
				key_held[.Forward] = true
			}

			if e.key_code == .S {
				key_held[.Backward] = true
			}

			if e.key_code == .A {
				key_held[.Left] = true
			}

			if e.key_code == .D {
				key_held[.Right] = true
			}

		case .KEY_UP:
			if e.key_code == .W {
				key_held[.Forward] = false
			}

			if e.key_code == .S {
				key_held[.Backward] = false
			}
			
			if e.key_code == .A {
				key_held[.Left] = false
			}

			if e.key_code == .D {
				key_held[.Right] = false
			}

		case .MOUSE_DOWN:
			if e.mouse_button == .LEFT {
				mouse_held[.Left] = true
			}

			if e.mouse_button == .RIGHT {
				mouse_held[.Right] = true
			}


		case .MOUSE_UP:
			if e.mouse_button == .LEFT {
				mouse_held[.Left] = false
			}

			if e.mouse_button == .RIGHT {
				mouse_held[.Right] = false
			}
	}
}

main :: proc() {
	default_context = context

	sapp.run({
		init_cb = init,
		frame_cb = frame,
		cleanup_cb = cleanup,
		event_cb = event,
		width = 1280,
		height = 720,
		high_dpi = true,
		window_title = "Landscapin",
		icon = { sokol_default = true },
		logger = { func = slog.func },
	})
}
