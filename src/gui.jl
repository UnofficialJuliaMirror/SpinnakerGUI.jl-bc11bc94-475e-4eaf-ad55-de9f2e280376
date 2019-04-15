using CImGui
using CImGui.CSyntax
using CImGui.GLFWBackend
using CImGui.OpenGLBackend
using CImGui.GLFWBackend.GLFW
using CImGui.OpenGLBackend.ModernGL
using CImGui.CSyntax.CStatic
using CImGui: ImVec2, ImVec4, IM_COL32, ImS32, ImU32, ImS64, ImU64

using Printf
using Random, FixedPointNumbers

include("gui/gui_control.jl")

preview_img_width = 800
previewscale = preview_img_width/camSettings.width
preview_img_height = round(Int,camSettings.height * previewscale)

function gui(;timerInterval::AbstractFloat=1/60)
    global gui_open, control_open, demo_open
    global camSettings, camGPIO

    @static if Sys.isapple()
        # GL_LUMINANCE not available >= 3.0
        # OpenGL 2.1 + GLSL 120
        glsl_version = 120
        GLFW.WindowHint(GLFW.CONTEXT_VERSION_MAJOR, 2)
        GLFW.WindowHint(GLFW.CONTEXT_VERSION_MINOR, 1)
        #GLFW.WindowHint(GLFW.OPENGL_PROFILE, GLFW.OPENGL_CORE_PROFILE) # 3.2+ only
        #GLFW.WindowHint(GLFW.OPENGL_FORWARD_COMPAT, GL_TRUE) # required on Mac 3.0+ only
    else
        # OpenGL 3.0 + GLSL 130
        glsl_version = 120
        GLFW.WindowHint(GLFW.CONTEXT_VERSION_MAJOR, 2)
        GLFW.WindowHint(GLFW.CONTEXT_VERSION_MINOR, 1)
        # GLFW.WindowHint(GLFW.OPENGL_PROFILE, GLFW.OPENGL_CORE_PROFILE) # 3.2+ only
        # GLFW.WindowHint(GLFW.OPENGL_FORWARD_COMPAT, GL_TRUE) # 3.0+ only
    end


    # setup GLFW error callback
    error_callback(err::GLFW.GLFWError) = @error "GLFW ERROR: code $(err.code) msg: $(err.description)"
    GLFW.SetErrorCallback(error_callback)

    # create window
    v = get_my_version()
    window = GLFW.CreateWindow(1280, 720, "SpinnakerGUI v$v")
    @assert window != C_NULL
    GLFW.MakeContextCurrent(window)
    GLFW.SwapInterval(0)  # disable vsync
    #GLFW.SwapInterval(1)  # enable vsync

    # setup Dear ImGui context
    ctx = CImGui.CreateContext()

    # setup Dear ImGui style
    CImGui.StyleColorsDark()
    # CImGui.StyleColorsClassic()
    # CImGui.StyleColorsLight()

    # load Fonts
    # - If no fonts are loaded, dear imgui will use the default font. You can also load multiple fonts and use `CImGui.PushFont/PopFont` to select them.
    # - `CImGui.AddFontFromFileTTF` will return the `Ptr{ImFont}` so you can store it if you need to select the font among multiple.
    # - If the file cannot be loaded, the function will return C_NULL. Please handle those errors in your application (e.g. use an assertion, or display an error and quit).
    # - The fonts will be rasterized at a given size (w/ oversampling) and stored into a texture when calling `CImGui.Build()`/`GetTexDataAsXXXX()``, which `ImGui_ImplXXXX_NewFrame` below will call.
    # - Read 'fonts/README.txt' for more instructions and details.
    # fonts_dir = "gui/fonts"
    # fonts = CImGui.GetIO().Fonts
    # default_font = CImGui.AddFontDefault(fonts)
    # CImGui.AddFontFromFileTTF(fonts, joinpath(fonts_dir, "Cousine-Regular.ttf"), 15)
    # CImGui.AddFontFromFileTTF(fonts, joinpath(fonts_dir, "DroidSans.ttf"), 16)
    # CImGui.AddFontFromFileTTF(fonts, joinpath(fonts_dir, "Karla-Regular.ttf"), 10)
    # CImGui.AddFontFromFileTTF(fonts, joinpath(fonts_dir, "ProggyTiny.ttf"), 10)
    # CImGui.AddFontFromFileTTF(fonts, joinpath(fonts_dir, "Roboto-Medium.ttf"), 16)
    # @assert default_font != C_NULL

    # creat texture for image drawing
    image_id = ImGui_ImplOpenGL3_CreateImageTexture(camSettings.width, camSettings.height)

    # setup Platform/Renderer bindings
    ImGui_ImplGlfw_InitForOpenGL(window, true)
    ImGui_ImplOpenGL3_Init(glsl_version)

    clear_color = Cfloat[0.45, 0.55, 0.60, 1.00]

    looptime = 0.0
    gui_timer = Timer(0,interval=timerInterval)
    while !GLFW.WindowShouldClose(window)
        t_before = time()
        io = CImGui.GetIO()

        GLFW.PollEvents()
        # start the Dear ImGui frame
        ImGui_ImplOpenGL3_NewFrame()
        ImGui_ImplGlfw_NewFrame()
        CImGui.NewFrame()

        control_open && @c ShowControlWindow(&control_open)

        # show image example
        CImGui.Begin("Raw Video Preview")
        pos = CImGui.GetCursorScreenPos()

        ImGui_ImplOpenGL3_UpdateImageTexture(image_id, camImage, camSettings.width, camSettings.height,format=GL_LUMINANCE,type=GL_UNSIGNED_BYTE)

        CImGui.Image(Ptr{Cvoid}(image_id), (preview_img_width, preview_img_height))
        if CImGui.IsItemHovered()
            CImGui.BeginTooltip()
            region_sz = 32.0

            region_x = io.MousePos.x - pos.x - region_sz * 0.5
            region_x = clamp(region_x,0.0,preview_img_width - region_sz)

            region_y = io.MousePos.y - pos.y - region_sz * 0.5
            region_y = clamp(region_y,0.0,preview_img_height - region_sz)

            zoom = 4.0
            #CImGui.Text(@sprintf("Min: (%d, %d)", region_x, region_y))
            #CImGui.Text(@sprintf("Max: (%d, %d)", region_x + region_sz, region_y + region_sz))
            uv0 = ImVec2(region_x / preview_img_width, region_y / preview_img_height)
            uv1 = ImVec2((region_x + region_sz) / preview_img_width, (region_y + region_sz) / preview_img_height)
            CImGui.Image(Ptr{Cvoid}(image_id), ImVec2(region_sz * zoom, region_sz * zoom), uv0, uv1, (255,255,255,255), (255,255,255,128))
            CImGui.EndTooltip()
        end

        CImGui.End()

        # rendering
        CImGui.Render()
        GLFW.MakeContextCurrent(window)
        display_w, display_h = GLFW.GetFramebufferSize(window)
        glViewport(0, 0, display_w, display_h)
        glClearColor(clear_color...)
        glClear(GL_COLOR_BUFFER_BIT)
        ImGui_ImplOpenGL3_RenderDrawData(CImGui.GetDrawData())

        GLFW.MakeContextCurrent(window)
        GLFW.SwapBuffers(window)

        if time()-t_before < timerInterval
            wait(gui_timer)
        else
            yield()
        end
    end
    close(gui_timer)
    # cleanup
    ImGui_ImplOpenGL3_Shutdown()
    ImGui_ImplGlfw_Shutdown()
    CImGui.DestroyContext(ctx)

    GLFW.DestroyWindow(window)
    gui_open = false
end
