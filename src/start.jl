const DEFAULT_COMMANDS  = Dict("help"     => Help.help,
                               "type"     => Keyboard.type,
                               "email"    => Email.email,
                               "internet" => Internet.internet)

"""
    start()
    start(<keyword arguments>)

Start offline, low latency, highly accurate and secure speech to command translation.

# Keyword arguments
- `command_language::String="$(LANG.EN_US)"`: the language of the voice commands (noted with its IETF langauge tag https://en.wikipedia.org/wiki/IETF_language_tag). Currently supported are: english-US ("en-us"), German ("de"), French ("fr") and Spanish ("es").
- `type_languages::String|AbstractArray{String}=["$(LANG.EN_US)"]`: the languages used for typing (noted with its IETF langauge tag https://en.wikipedia.org/wiki/IETF_language_tag). Currently supported are: english-US ("en-us"), German ("de"), French ("fr") and Spanish ("es"). Type `?Keyboard.type` for information about typing or say "help type" after having started JustSayIt.
- `commands::Dict{String, <:Any}=DEFAULT_COMMANDS[command_language]`: the commands to be recognized with their mapping to a function or to a keyboard key or shortcut.
- `subset::AbstractArray{String}=nothing`: a subset of the `commands` to be recognised and executed (instead of the complete `commands` list).
- `max_speed_subset::AbstractArray{String}=nothing`: a subset of the `commands` for which the command names (first word of a command) are to be recognised with maxium speed rather than with maximum accuracy. Forcing maximum speed is usually desired for single word commands that map to functions or keyboard shortcuts that should trigger immediate actions as, e.g., mouse clicks or page up/down (in general, actions that do not modify content and can therefore safely be triggered at maximum speed). Note that forcing maximum speed means not to wait for a certain amount of silence after the end of a command as normally done for the full confirmation of a recognition. As a result, it enables a minimal latency between the saying of a command name and its execution. Note that it is usually possible to define very distinctive command names, which allow for a safe command name to shortcut mapping at maximum speed (to be tested case by case).
!!! note "Advanced"
    - `modeldirs::Dict{String, String}=DEFAULT_MODELDIRS[command_language,type_languages]`: the directories where the unziped speech recognition models to be used are located. Models are downloadable from here: https://alphacephei.com/vosk/models
    - `noises::Dict{String, <:AbstractArray{String}}=DEFAULT_NOISES[command_language,type_languages]`: for each model, an array of strings with noises (tokens that are to be ignored in the speech as, e.g., "huh").
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

!!! note "Advanced"
    # Default `modeldirs`
    ```
    $(pretty_dict_string(DEFAULT_MODELDIRS))
    ```

    # Default `noises`
    ```
    $(pretty_dict_string(DEFAULT_NOISES))
    ```

# Examples

#### Define `command_language` and `type_languages`
```
# Set command language to french and type languages to french and spanish:
using JustSayIt
start(command_language="$(LANG.FR)", type_languages=["$(LANG.FR)","$(LANG.ES)"])
```

#### Define `subset`
```
# Listen only to the commands "help" and "type".
using JustSayIt
start(subset=["help", "type"])
```

#### Define custom `commands` - functions and keyboard shortcuts - and a `max_speed_subset`
```
using JustSayIt
commands = Dict("help"      => Help.help,
                "type"      => Keyboard.type,
                "ma"        => Mouse.click_left,
                "select"    => Mouse.press_left,
                "okay"      => Mouse.release_left,
                "middle"    => Mouse.click_middle,
                "right"     => Mouse.click_right,
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
start(commands=commands, max_speed_subset=["ma", "select", "okay", "middle", "right", "double", "triple", "copy", "upwards", "downwards"])
```

#### Define custom `modeldirs`
```
using JustSayIt
modeldirs = Dict(MODELNAME.DEFAULT.EN_US => "$(homedir())/mymodels/vosk-model-small-en-us-0.15",
                 MODELNAME.TYPE.EN_US    => "$(homedir())/mymodels/vosk-model-en-us-daanzu-20200905")
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
function start(; command_language::String=LANG.EN_US, type_languages::Union{String,AbstractArray{String}}=LANG.EN_US, commands::Dict{String, <:Any}=DEFAULT_COMMANDS, subset::Union{Nothing, AbstractArray{String}}=nothing, max_speed_subset::Union{Nothing, AbstractArray{String}}=nothing, modeldirs::Dict{String,String}=DEFAULT_MODELDIRS, noises::Dict{String,<:AbstractArray{String}}=DEFAULT_NOISES, audio_input_cmd::Union{Cmd,Nothing}=nothing) where N
    if (!isnothing(subset) && !issubset(subset, keys(commands))) @IncoherentArgumentError("'subset' incoherent: the obtained command name subset ($(subset)) is not a subset of the command names ($(keys(commands))).") end
    if (!isnothing(max_speed_subset) && !issubset(max_speed_subset, keys(commands))) @IncoherentArgumentError("'max_speed_subset' incoherent: the obtained max_speed_subset ($(max_speed_subset)) is not a subset of the command names ($(keys(commands))).") end
    if !isnothing(subset) commands = filter(x -> x[1] in subset, commands) end
    if isnothing(max_speed_subset) max_speed_subset = String[] end
    max_speed_token_subset = map(max_speed_subset) do cmd_name # Only the first tokens are used to decide if max speed is used.
       string(first(split(cmd_name)))
    end
    max_speed_multiword_cmds = [x for x in keys(commands) if any(startswith.(x, [x for x in max_speed_token_subset if x ∉ max_speed_subset]))]
    incoherent_subset = [x for x in max_speed_multiword_cmds if x ∉ max_speed_subset]
    if !isempty(incoherent_subset) @IncoherentArgumentError("'max_speed_subset' incoherent: the following commands are not part of 'max_speed_subset', but start with the same word as a command that is part of it: \"$(join(incoherent_subset,"\", \"", " and "))\". Adjust the 'max_speed_subset' to prevent this.") end

    # Initializations
    @info "JustSayIt: I am initializing (say \"sleep JustSayIt\" to put me to sleep; press CTRL+c to terminate)..."
    init_jsi(commands, modeldirs, noises)
    start_recording(; audio_input_cmd=audio_input_cmd)

    # Interprete commands
    @info "Listening for commands..."
    valid_cmd_names = command_names()
    cmd_name = ""
    is_sleeping = false
    use_max_speed = true
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
                        latency_msg = use_max_speed ? " (latency: $(round(Int,toc(t0_latency())*1000)) ms)" : ""
                        @info "Starting command: $(pretty_cmd_string(cmd))"*latency_msg
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
                    @debug "Invalid command: $cmd_name."
                end
            end
            try
                force_reset_previous(recognizer(COMMAND_RECOGNIZER_ID))
                use_max_speed = _is_next(max_speed_token_subset, recognizer(COMMAND_RECOGNIZER_ID), _noises(MODELNAME.DEFAULT.EN_US); use_partial_recognitions=true, ignore_unknown=false)
                cmd_name = next_token(recognizer(COMMAND_RECOGNIZER_ID), _noises(MODELNAME.DEFAULT.EN_US); use_partial_recognitions = use_max_speed, ignore_unknown=false)
                if cmd_name == UNKNOWN_TOKEN # For increased recognition security, ignore the current word group if the unknown token was obtained as command name (achieved by doing a full reset). This will prevent for example "text right" or "text type text" to trigger an action, while "right" or "type text" does so.
                    reset_all()
                    cmd_name = ""
                end
                while (cmd_name != "") && (cmd_name ∉ valid_cmd_names) && any(startswith.(valid_cmd_names, cmd_name))
                    token = next_token(recognizer(COMMAND_RECOGNIZER_ID), _noises(MODELNAME.DEFAULT.EN_US); use_partial_recognitions = use_max_speed, ignore_unknown=false)
                    if token == UNKNOWN_TOKEN # For increased recognition security, ignore the current word group if the unknown token was obtained as command name (achieved by doing a full reset). This will prevent for example "text right" or "text type text" to trigger an action, while "right" or "type text" does so.
                        reset_all()
                        cmd_name = ""
                    else
                        cmd_name = cmd_name * " " * token
                    end
                end
            catch e
                if isa(e, InsecureRecognitionException)
                    if !is_sleeping @debug(e.msg) end
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

@voiceargs words=>(valid_input=["just say it"], vararg_timeout=2.0, vararg_max=3) function _is_confirmed(words::String...)
    return (join(words, " ") == "just say it")
end

execute(cmd::Function)                  = cmd()
execute(cmd::PyKey)                     = Keyboard.press_keys(cmd)
execute(cmd::NTuple{N,PyKey} where {N}) = Keyboard.press_keys(cmd...)
