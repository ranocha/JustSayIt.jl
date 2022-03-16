const DEFAULT_COMMANDS  = Dict("help"     => Help.help,
                               "type"     => Keyboard.type,
                               "ma"       => Mouse.click_left,
                               "select"   => Mouse.press_left,
                               "okay"     => Mouse.release_left,
                               "middle"   => Mouse.click_middle,
                               "right"    => Mouse.click_right,
                               "double"   => Mouse.click_double,
                               "triple"   => Mouse.click_triple,
                               "email"    => Email.email,
                               "internet" => Internet.internet)

"""
    start()
    start(<keyword arguments>)

Start offline, low latency, highly accurate speech to command translation.

# Keyword arguments
- `commands::Dict{String, <:Any}=DEFAULT_COMMANDS`: the commands to be recognized with their mapping to a function or to a keyboard key or shortcut.
- `subset::NTuple{N,String}=nothing`: a subset of the `commands` to be recognised and executed (instead of the complete `commands` list).
- `use_max_accuracy::Bool=false`: whether to use maxium accuracy for the recognition of the command names (rather than maximum speed). It is recommended to set `use_max_accuracy=true` if command names map to keyboard shortcuts triggering immediate actions, as this allows for a safe recognition of such single word commands. There will however be a perceivable latency between the saying of a command and its execution. Alternatively to setting `use_max_accuracy=true`, it is possible to define very distinctive command names in order to achive a safe command name to shortcut mapping (to be tested always).
- `modeldirs::Dict{String, String}=DEFAULT_MODELDIRS`: the directories where the unziped speech recognition models to be used are located. Models are downloadable from here: https://alphacephei.com/vosk/models
- `noises::Dict{String, <:AbstractArray{String}}=DEFAULT_NOISES`: for each model, an array of strings with noises (tokens that are to be ignored in the speech as, e.g., "huh").
- `audio_input_cmd::Cmd=nothing`: a command that returns an audio stream to replace the default audio recorder. The audio stream must fullfill the following properties: `samplerate=$SAMPLERATE`, `channels=$AUDIO_IN_CHANNELS` and `format=Int16` (signed 16-bit integer).

# Submodules for command name to function mapping
- [`Help`](@ref)
- [`Keyboard`](@ref)
- [`Mouse`](@ref)
- [`Email`](@ref)
- [`Internet`](@ref)

To see a description of a submodule, type `?<modulename>`.

# Default `commands`
```
$(pretty_dict_string(DEFAULT_COMMANDS))
```

# Default `modeldirs`
```
$(pretty_dict_string(DEFAULT_MODELDIRS))
```

# Default `noises`
```
$(pretty_dict_string(DEFAULT_NOISES))
```

# Examples

#### Define `subset`
```
# Listen to all commands with exception of the mouse button commands.
using JustSayIt
start(subset=("help", "type", "email", "internet"))
```

```
# Listen only to the mouse button commands.
using JustSayIt
start(subset=("ma", "select", "okay", "middle", "right", "double", "triple"))
```

#### Define custom `commands` - functions and keyboard shortcuts
```
using JustSayIt
commands = Dict("help"      => Help.help,
                "type"      => Keyboard.type,
                "double"    => Mouse.click_double,
                "triple"    => Mouse.click_triple,
                "copy"      => (Key.ctrl, 'c'),
                "cut"       => (Key.ctrl, 'x'),
                "paste"     => (Key.ctrl, 'v'),
                "undo"      => (Key.ctrl, 'z'),
                "redo"      => (Key.ctrl, Key.shift, 'z'),
                "upwards"   => Key.page_up,
                "downwards" => Key.page_down,
                );
start(commands=commands)
```

#### Define custom `modeldirs`
```
using JustSayIt
modeldirs = Dict(DEFAULT_MODEL_NAME => "$(homedir())/mymodels/vosk-model-small-en-us-0.15",
                 TYPE_MODEL_NAME    => "$(homedir())/mymodels/vosk-model-en-us-daanzu-20200905")
start(modeldirs=modeldirs)
```

#### Define `audio_input_cmd`
```
# Use a custom command to create the audio input stream - instead of the default recorder (the rate, channels and format must not be chosen different!)
using JustSayIt
audio_input_cmd = `arecord --rate=$SAMPLERATE --channels=$AUDIO_IN_CHANNELS --format=S16_LE`
start(audio_input_cmd=audio_input_cmd)
```
"""
function start(; commands::Dict{String, <:Any}=DEFAULT_COMMANDS, subset::Union{Nothing, NTuple{N,String}}=nothing, use_max_accuracy::Bool=false, modeldirs::Dict{String,String}=DEFAULT_MODELDIRS, noises::Dict{String,<:AbstractArray{String}}=DEFAULT_NOISES, audio_input_cmd::Union{Cmd,Nothing}=nothing) where N
    if (!isnothing(subset) && !issubset(subset, keys(commands))) error("obtained command name subset ($(subset)) is not a subset of the command names ($(keys(commands))).") end
    if !isnothing(subset) commands = filter(x -> x[1] in subset, commands) end

    # Initializations
    @info "Initializing JustSayIt (press CTRL+c to terminate JustSayIt)..."
    init_jsi(commands, modeldirs, noises)
    start_recording(; audio_input_cmd=audio_input_cmd)

    # Interprete commands
    @info "Listening for commands..."
    valid_cmd_names = command_names()
    cmd_name = ""
    is_sleeping = false
    try
        while true
            if is_sleeping
                if cmd_name == COMMAND_NAME_AWAKE
                    if is_confirmed() is_sleeping = false end
                    if (is_sleeping) @info("I heard \"awake\". If you want to awake me, say \"awake JustSayIt\".")
                    else             @info("... awake again. Listening for commands...")
                    end
                end
            else
                if cmd_name in valid_cmd_names
                    cmd = command(string(cmd_name))
                    if (t0_latency() > 0.0) @debug "Latency of command `$cmd_name`: $(round(toc(t0_latency()),sigdigits=2))." end
                    try
                        @info "Starting command: $(pretty_cmd_string(cmd)) (latency: $(round(Int,toc(t0_latency())*1000)) ms)"
                        execute(cmd)
                    catch e
                        if isa(e, InsecureRecognitionException)
                            @info("Command `$cmd_name` aborted: insecure command argument recognition.")
                        elseif isa(e, InterruptException)
                            @info "Command `$cmd_name` aborted (with CTRL+C)."
                        else
                            rethrow(e)
                        end
                    end
                elseif cmd_name == COMMAND_NAME_SLEEP
                    if is_confirmed() is_sleeping = true end
                    if (!is_sleeping) @info("I heard \"sleep\". If you want me to sleep, say \"sleep JustSayIt\".")
                    else              @info("Going to sleep... (To awake me, just say \"awake JustSayIt\".)")
                    end
                elseif cmd_name != ""
                    @info "Invalid command: $cmd_name." # NOTE: this might better go to stderr or @debug later.
                end
            end
            try
                force_reset_previous(recognizer(COMMAND_RECOGNIZER_ID))
                cmd_name = next_token(recognizer(COMMAND_RECOGNIZER_ID), _noises(DEFAULT_MODEL_NAME); use_partial_recognitions = true)
            catch e
                if isa(e, InsecureRecognitionException)
                    if !is_sleeping @info(e.msg) end
                    cmd_name = ""
                else
                    rethrow(e)
                end
            end
        end
    catch e
        if isa(e, InterruptException)
            @info "Terminating JustSayIt..."
        else
            rethrow(e)
        end
    finally
        stop_recording()
        @info "Stopped listening for commands."
    end

    finalize_jsi()
end

function is_confirmed()
    try
        _is_confirmed()
    catch e
        if isa(e, InsecureRecognitionException)
            return false
        else
            rethrow(e)
        end
    end
end

@voiceargs words=>(valid_input=["just say it"], use_max_accuracy=true, vararg_timeout=2.0, vararg_max=3) function _is_confirmed(words::String...)
    return (join(words, " ") == "just say it")
end

execute(cmd::Function)                  = cmd()
execute(cmd::PyKey)                     = Keyboard.press_keys(cmd)
execute(cmd::NTuple{N,PyKey} where {N}) = Keyboard.press_keys(cmd...)
