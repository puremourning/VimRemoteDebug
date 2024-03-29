" Vim global plugin for remote debugging with vimspector
" Last Change:  20 Oct 2014
" Maintainer:   Ben Jackson
"

" Basic vim plugin boilerplate {{{
let s:save_cpo = &cpo
set cpo&vim
"}}}

if exists("s:remotedebug_initialised")
    finish
endif
let s:remotedebuf_initialised = 1

" utilities for working around Vim foilbles {{{
function! s:expand( str )
    " note the second expand() parameter tells it to ignore wildignore!
    return expand( a:str, 1 )
endfunction
" }}}

" global run-once {{{
" Dictionary mapping profile name on to dictionary of profile parameters
let s:profiles={}
let s:current_profile=''
let s:reset_cmd=''
let s:script_folder_path = escape( s:expand( '<sfile>:p:h' ), '\' ) . "/../keys"
"}}}

" utilities for output {{{
function! s:error(msg)
    echohl ErrorMsg
    echo a:msg
    call inputsave()
    call input("Press the <Enter> key to continue.")
    call inputrestore()
    echohl None
endfunction

function! s:info(msg)
    echo a:msg
endfunction

function! s:warning(msg)
    echohl WarningMsg
    echo a:msg
    echohl None
endfunction
"}}}

" functions for profiles {{{
function! remotedebug#WriteProfile(name,binary,creds,gdbserver,runCmd,pidCmd)
    " todo: perhaps we should use a dictionary->list or something?
    if empty(a:gdbserver)
        let l:gdbserver = g:remotedebug_gdbserver
    else
        let l:gdbserver = a:gdbserver
    endif

    call extend(s:profiles, {
        \ a:name : {
            \ 'binary':    a:binary,
            \ 'creds':     a:creds,
            \ 'gdbserver': l:gdbserver,
            \ 'runCmd':    a:runCmd,
            \ 'pidCmd':    a:pidCmd
        \ }
    \ })
endfunction

function! remotedebug#LoadProfile(...)
    if a:0 == 1
        let l:name = a:1
        if !exists('s:profiles[l:name]')
            let s:current_profile = ''
            call s:error("Unknown profile: " . l:name)
        else
            let s:current_profile = l:name
        endif
    elseif a:0 == 0
        call s:info('Listing all profiles ...')
        call s:info(join(keys(s:profiles), "\n") )
    else
        call s:error('Wrong number of arguments')
    endif
endfunction

function! remotedebug#CompleteProfile(ArgLead, CmdLine, CursorPos)
    return join(keys(s:profiles), "\n")
endfunction


function! remotedebug#GetCurrentProfile()
    if empty( s:current_profile )
        return {}
    endif
    let prof = deepcopy( s:profiles[s:current_profile] )

    if prof.creds =~ '^docker://'
        let prof.container = strpart( prof.creds, len( 'docker://' ) )
        unlet prof.creds
    endif
    return prof
endfunction
"}}}

" Run and Attach {{{
function! s:StartPyClewn()
    if has('netbeans_enabled')
        " already running, just reset any active debugging session 
        call s:ResetRunning()
        return 1
    endif

    " The best way to specify the args is trhough the global veriable (due to
    " multiple escaping?)
    let g:pyclewn_args="--gdb=async"
    execute "Pyclewn gdb"
    call s:info("Waiting for pyclewn...(1 secs)")
    sleep 1

    " no way to detect failure of Pyclewn?
    if !has('netbeans_enabled')
        call s:error("Pyclewn failed to start ?")
        return 0
    endif

    " When vim exists ensure that we reset so that any running processes and
    " gdbserver instances don't get left behind
    augroup remotedebug
        autocmd!
        autocmd VimLeavePre * call remotedebug#Reset()
    augroup END

    return 1
endfunction

function! s:Connect(profile, port)

    " Open the file and load symbols
    execute "Cfile " . s:expand(a:profile['binary'])
    sleep 500m

    " Debugging into shared libraries
    "
    " tell the local debugger to get remote system libs etc. by copying them
    " to the local system. When remote debugging in gdb you're required to have
    " copies (e.g. like a chroot) of the remote system libs if they differ in
    " any way from the local system. that's likely due to various patches, so we
    " just copy them across as needed.
    execute "Cset sysroot remote:/"
    sleep 500m

    " set up the remote target (gdbserver should already be attached)
    execute "Ctarget remote "
        \ . split(a:profile['creds'], '\v\@')[1] 
        \ . ':'
        \ . a:port
    sleep 500m

    if g:remotedebug_auto_map_keys
        " Map keys if configured to do so.
        Cmapkeys
        sleep 200m
    endif

    if !exists("g:remotedebug_no_open_vars")
        Cdbgvar
    endif

    " and... I think we're done
    call s:info("Ready to go... you might have to wait a bit for it to kick in")
endfunction

function! remotedebug#Run(port, ...)
    " if they supplied a profile name, load it
    if a:0 != 0
        call remotedebug#LoadProfile(a:1)
    endif

    " if they supplied a port, use it, else use the default
    if a:port <= 0
        let l:port = g:remotedebug_port
    else
        let l:port = a:port
    endif

    if empty(s:current_profile)
        call s:warning("No profile selected. Call DebugProfile")
        return
    endif

    let l:profile = s:profiles[s:current_profile]

    if ! s:StartPyClewn()
        return
    endif

    " We started, so we kill the process
    let s:reset_cmd='Ckill'

    let l:command = l:profile['gdbserver'] 
                \ . ' :'
                \ . l:port
                \ . ' '
                \ . shellescape(l:profile['runCmd'])
                \ . ' | tee ~/.remotedebug_log &'

    let l:out = system('ssh ' . l:profile['creds'] . ' ' . l:command)
    sleep 500m

    call s:Connect(l:profile, l:port)

    " show the log file TODO: use Dispatch
    call s:ShowLog('~/.remotedebug_log')
endfunction

function! remotedebug#LoadHostOnly( credentials )
    let l:name = 'TemporaryHostOnly'
    call remotedebug#WriteProfile(
                \ l:name,
                \ '/bin/echo', 
                \ a:credentials,
                \ '',
                \ '/bin/echo',
                \ '/bin/false' )
    call remotedebug#LoadProfile( l:name )
    return l:name
endfunction

function! remotedebug#GetExecCmd( creds, cmd )
    if a:creds =~# '^docker://'
        let c = strpart( a:creds, len( 'docker://' ) )->split( ' ' )
        let container = c[ 0 ]
        if len( c ) > 1
            let launcher = c->slice( 1 )->join( ' ' )
        else
            let launcher = '/bin/csh'
        endif
        return 'docker exec ' . container
                    \ . ' ' . launcher . ' -c "'
                    \ . a:cmd
                    \ . '"'
    else
        return 'ssh ' . a:creds . ' ' . a:cmd
    endif
endfunction

function s:Dispatch( cmd )
    let s = &shell
    set shell=/bin/bash
    try
        execute a:cmd
    finally
        let &shell = s
    endtry
endfunction

function! remotedebug#Dispatch( ... )
    if a:0 > 1
        let l:credentials = a:1
        let l:command = a:2
    else
        if empty(s:current_profile)
            call s:warning(
                \ "No debug profile or host credentials selected. " .
                \ "Call :DebugHost or :DebugProfile to set one, or " .
                \ "directly call :DebugDispatch <creds> <command>" )
            return
        endif

        let l:profile = s:profiles[ s:current_profile ]
        let l:credentials = l:profile[ 'creds' ]
        let l:command = a:1
    endif
    

    call s:Dispatch( 
        \ 'Dispatch ' . remotedebug#GetExecCmd( l:credentials, l:command ) )
endfunction

function! remotedebug#DispatchCompiler( compiler, ... )
    if a:0 > 1
        let l:credentials = a:1
        let l:command = a:2
    else
        if empty(s:current_profile)
            call s:warning(
                \ "No debug profile or host credentials selected. " .
                \ "Call :DebugHost or :DebugProfile to set one, or " .
                \ "directly call :DebugDispatch <creds> <command>" )
            return
        endif

        let l:profile = s:profiles[ s:current_profile ]
        let l:credentials = l:profile[ 'creds' ]
        let l:command = a:1
    endif
    
    call s:Dispatch( 'Dispatch -compiler=' 
                \ . a:compiler 
                \ . ' '
                \ . remotedebug#GetExecCmd( l:credentials, l:command ) )
endfunction

function! remotedebug#Attach(port, ...)
    " if they supplied a profile name, load it
    let l:profile = ""
    let l:pid = 0
    if a:0 > 1 && a:1 == "-pid"
        let l:pid = a:2

        if a:0 > 2
            let l:profile = a:3
        endif
    elseif a:0 != 0
        let l:profile = a:1
    endif

    if l:profile != ""
        call remotedebug#LoadProfile(l:profile)
    endif

    " if they supplied a port, use it, else use the default
    if a:port <= 0
        let l:port = g:remotedebug_port
    else
        let l:port = a:port
    endif

    if empty(s:current_profile)
        call s:warning("No profile selected. Call DebugProfile")
        return
    endif

    let l:profile = s:profiles[s:current_profile]

    if ! s:StartPyClewn()
        return
    endif

    " We didn't start the process so detach on Reset
    let s:reset_cmd='Cdetach'

    " find the pid
    if l:pid <= 0
        let l:pid_out = system('ssh ' 
                            \ . l:profile['creds'] 
                            \ .  ' ' 
                            \ . l:profile['pidCmd']
                            \ . '| tee ~/.remotedebug_log')
        
        " hack: ExecTclProc.. puts a newline on the end?
        let l:pid = split(l:pid_out, '\v\n')[0]
    endif

    if l:pid <= 0
        call s:error("Unable to get pid (return: " 
                    \ . l:pid 
                    \ . "). Is it running?")
        return
    endif

    " start gdbserver remotely
    let l:command = l:profile['gdbserver'] 
                \ . ' --attach :'
                \ . l:port 
                \ . ' '
                \ . l:pid
                \ . ' | tee ~/.remotedebug_log &'

    call system('ssh ' . l:profile['creds'] . ' ' . l:command)
    sleep 500m

    call s:Connect(l:profile, l:port)

endfunction

function! s:ConnectTermDebug(profile, port)
    " Nothing yet
    echom "GDB server  running on port " . a:port

    "execute "TermdebugCommand file " . s:expand(a:profile['binary'])
    "execute "TermdebugCommand set sysroot remote:/"
    "execute "TermdebugCommand target remote "
    "    \ . split(a:profile['creds'], '\v\@')[1] 
    "    \ . ':'
    "    \ . a:port
endfunction

function! remotedebug#AttachTermDebug(port, ...)
    " if they supplied a profile name, load it
    let l:profile = ""
    let l:pid = 0
    if a:0 > 1 && a:1 == "-pid"
        let l:pid = a:2

        if a:0 > 2
            let l:profile = a:3
        endif
    elseif a:0 != 0
        let l:profile = a:1
    endif

    if l:profile != ""
        call remotedebug#LoadProfile(l:profile)
    endif

    " if they supplied a port, use it, else use the default
    if a:port <= 0
        let l:port = g:remotedebug_port
    else
        let l:port = a:port
    endif

    if empty(s:current_profile)
        call s:warning("No profile selected. Call DebugProfile")
        return
    endif

    let l:profile = s:profiles[s:current_profile]

    " TODO: Some TermDebug command here
    let s:reset_cmd=''

    " find the pid
    if l:pid <= 0
        let l:pid_out = system('ssh ' 
                            \ . l:profile['creds'] 
                            \ .  ' ' 
                            \ . l:profile['pidCmd']
                            \ . '| tee ~/.remotedebug_log')
        
        " hack: ExecTclProc.. puts a newline on the end?
        let l:pid = split(l:pid_out, '\v\n')[0]
    endif

    if l:pid <= 0
        call s:error("Unable to get pid (return: " 
                    \ . l:pid 
                    \ . "). Is it running?")
        return
    endif

    " start gdbserver remotely
    let l:command = l:profile['gdbserver'] 
                \ . ' --attach :'
                \ . l:port 
                \ . ' '
                \ . l:pid
                \ . ' | tee ~/.remotedebug_log &'

    call system('ssh ' . l:profile['creds'] . ' ' . l:command)
    sleep 500m

    call s:ConnectTermDebug(l:profile, l:port)
endfunction

" Kill any currently running debug session, but don't close down pyclewn
function! s:ResetRunning()
    if has('netbeans_enabled') && !empty(s:reset_cmd)
        " we need to interrupt the running process if it isn't already in a
        " debug break state. this is so that the reset command (Cdetach or
        " Ckill) can actually be processed by gdb. we do this by firing the
        " interrupt command (<CTRL-Z>)
        nbkey C-Z
        sleep 500m
        execute s:reset_cmd
        " it can take a little while to detach (according to pyclewn maintainer)
        sleep 1
        let s:reset_cmd = ''
    endif
endfunction

" close down any running session and pyclewn and unmap any mappings
" 
" This function is used to undo the effects of starting debuggin (for the most
" part anyway)
function! remotedebug#Reset()
    if g:remotedebug_auto_sync_symbols
        Cunmapkeys
        sleep 200m
    endif

    call s:ResetRunning()
    Cexitclewn
endfunction
" }}}

" viewing console output {{{
function! s:ShowLog(file)
    execute "Tail " . a:file
endfunction
" }}}

" GUI {{{
function! remotedebug#SetupGui()
    " Create the Debug menu
    if has("gui_running")
        for l:profile in keys(s:profiles)
            execute "noremenu <silent> &Debug.Load\\ &Profile." 
                        \ . l:profile 
                        \ . " :DebugProfile " 
                        \ . l:profile
                        \ . "<CR>"
        endfor

        noremenu <silent> &Debug.&Attach :DebugAttach 0<CR>
        noremenu <silent> &Debug.&Run    :DebugRun    0<CR>
        noremenu <silent> &Debug.R&eset  :DebugReset<CR>

        noremenu <silent> &Debug.-Separator- :

        " TODO: only enable these when actually debugging?
        noremenu <silent> &Debug.&Interrupt  :nbkey C-Z<CR>
        noremenu <silent> &Debug.Step\ &Over :Cnext<CR>
        noremenu <silent> &Debug.Step\ &Into :Cstep<CR>
        noremenu <silent> &Debug.Step\ O&ut  :Cfinish<CR>
        noremenu <silent> &Debug.&Continue   :Ccont<CR>

        noremenu <silent> &Debug.-Separator1- :

        noremenu <silent> &Debug.Set\ &Breakpoint   :nbkey C-B<CR>
        noremenu <silent> &Debug.Clea&r\ Breakpoint :nbkey C-E<CR>
    endif
endfunction

"}}}

" global run-once {{{
" load profiles
let s:profile_path = s:expand(g:remotedebug_profile_path)
if filereadable(s:profile_path)
    execute "source " . s:profile_path
endif
"}}}

" Basic vim plugin boilerplate {{{
let &cpo = s:save_cpo
unlet s:save_cpo
"  vim:tw=80:ts=8:sw=4:foldmethod=marker
"}}}
