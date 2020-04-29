" Vim global plugin for remote debugging with pyclewn
" Last Change:  20 Oct 2014
" Maintainer:   Ben Jackson


" Basic vim plugin boilerplate {{{
let s:save_cpo = &cpo
set cpo&vim

function! s:restore_cpo()
    let &cpo = s:save_cpo
    unlet s:save_cpo
endfunction

if exists( "g:loaded_remotedebug" )
    call s:restore_cpo()
    finish
elseif v:version < 704
    " need a new version
    call s:restore_cpo()
    finish
endif

let g:loaded_remotedebug = 1
"}}}

" Plugin global initialisation {{{
let s:plugin_path      = escape(expand('<sfile>:p:h'), '\')
let g:remotedebug_home = s:plugin_path."/../"
let g:remotedebug_port = get ( g:, 'remotedebug_port', 20001 )
let g:remotedebug_gdbserver = 
    \ get ( g:, 
          \ 'remotedebug_gdbserver',
          \ '/opt/rh/devtoolset-2/root/usr/bin/gdbserver')
let g:remotedebug_profile_path = 
    \ get ( g:,
          \ 'remotedebug_profile_path',
          \ '~/.remotedebug.profiles' )

let g:remotedebug_auto_map_keys = get(g:, 'remotedebug_auto_map_keys', 1)
let g:remotedebug_auto_sync_symbols = 
    \ get ( g:, 
          \ 'remotedebug_auto_sync_symbols', 
          \ 1)

"}}}

" Command: DebugProfileSet {{{
"
" The 'DebugProfileWrite' command writes a debug profile out to disk for re-use
" later with the 'DebugProfile' command. It also sets the current debug profile
" to the suppiled parameters
"
" Args:
"   0   - name of profile, for recall later
"   1   - path to the binary image on the local machine (output of :make)
"   2   - user@host for ssh access to remote host. 
"         suggest using passwordless ssh if possible to avoid entering password
"   3   - path to gdbserver on the remote host
"   4   - remote command to run the application with :DebugRun
"   5   - remote command to get the pid of the process with :DebugAttach
command! -nargs=* DebugProfileSet
            \ call remotedebug#WriteProfile(<f-args>)
"}}}

" Command: DebugProfile {{{
"
" The 'DebugProfile' command selects and loads a named debug profile as written
" by DebugProfileWrite
"
" Args:
"   0   - name of profile, for recall later
command! -nargs=* -complete=custom,remotedebug#CompleteProfile DebugProfile
            \ call remotedebug#LoadProfile(<f-args>)
"}}}

" Command: DebugHost {{{
"
" The 'DebugHost' command generates and ad-hoc profile with just the supplied
" credentials. This is useful when you just want to call DebugDispatch
"
" Args:
"   0   - credentials
command! -nargs=* DebugHost
            \ call remotedebug#LoadHostOnly(<f-args>)
"}}}

" Command: DebugDispatch {{{
"
" The 'DebugDispatch' command runs an arbitrary command using vim-dispatch on
" the remote host. This is useful, for example, to run your tests on a remote
" host and use Vim's errorformat, etc. to detect and report errors.
" 
" Note, call DebugProfile or DebugHost first.
"
" Args:
"   - (optional) the credentials to use, e.g. emma_tst@ukwok-pc1385-vpc
"   - the command to run, e.g. 'FidRun testKit_Test -f ...'
"   
command! -nargs=* DebugDispatch
            \ call remotedebug#Dispatch(<f-args>)
"}}}

" Command: DebugRun {{{
"
" The 'DebugRun' command starts dbuegging based on profile, runs up pyclewn 
" and netbeans interface, and attempts to run the process remotely
"
" Example:
" :DebugProfileWrite OrdSvr@dev-vm
"                 \ '$BUILD_ROOT/debug64/bin/emma_OrdSvr'
"                 \ 'emma_tst@ukwok-pc458'
"                 \ '/opt/rh/devtoolset-2/usr/bin/gdbserver'
"                 \ '$CASE/site-specific/bin64/emma_OrdSvr -c emma_OrdSvr.1.cfg'
"                 \ 'ExecTclProc -notrace Fid_ProcessRunning EMMA_ORDSVR_1' 
" :DebugProfile OrdSvr@dev-vm
" :DebugRun
"
" Example:
" :DebugProfileWrite OrdSvr@dev-vm
"                 \ '$BUILD_ROOT/debug64/bin/emma_OrdSvr'
"                 \ 'emma_tst@ukwok-pc458'
"                 \ '/opt/rh/devtoolset-2/usr/bin/gdbserver'
"                 \ '$CASE/site-specific/bin64/emma_OrdSvr -c emma_OrdSvr.1.cfg'
"                 \ 'ExecTclProc -notrace Fid_ProcessRunning EMMA_ORDSVR_1' 
" :DebugRun OrdSvr@dev-vm
command! -nargs=* -complete=custom,remotedebug#CompleteProfile DebugRun 
            \ call remotedebug#Run(<f-args>)
"}}}

" Command: DebugAtach {{{
"
" The 'DebugAtach' command starts debugging based on profile, runs up pyclewn 
" and netbeans interface, and attempts to attach to the process remotely
"
" Example:
" :DebugProfileWrite OrdSvr@dev-vm
"                 \ 'emma_tst@ukwok-pc458'
"                 \ '/opt/rh/devtoolset-2/usr/bin/gdbserver'
"                 \ '$BUILD_ROOT/debug64/bin/emma_OrdSvr'
"                 \ '$CASE/site-specific/bin64/emma_OrdSvr -c emma_OrdSvr.1.cfg'
"                 \ 'ExecTclProc -notrace Fid_ProcessRunning EMMA_ORDSVR_1' 
" :DebugProfile OrdSvr@dev-vm
" :DebugAttach
"
" Example:
" :DebugProfileWrite OrdSvr@dev-vm
"                 \ 'emma_tst@ukwok-pc458'
"                 \ '/opt/rh/devtoolset-2/usr/bin/gdbserver'
"                 \ '$BUILD_ROOT/debug64/bin/emma_OrdSvr'
"                 \ '$CASE/site-specific/bin64/emma_OrdSvr -c emma_OrdSvr.1.cfg'
"                 \ 'ExecTclProc -notrace Fid_ProcessRunning EMMA_ORDSVR_1' 
" :DebugAttach OrdSvr@dev-vm
"
command! -nargs=* -complete=custom,remotedebug#CompleteProfile DebugAttach
            \ call remotedebug#Attach(<f-args>)
"}}}

" Command: DebugAtachTerm {{{
"
" The 'DebugAtachServer' command starts debugging based on profile, but does not
" start PyClewn or the netbeans interface. Instead, it uses Vim's TermDebug
" feature.
"
" :DebugAttachTerm 0 MYPROFILE
"
command! -nargs=* -complete=custom,remotedebug#CompleteProfile DebugAttachTerm
            \ call remotedebug#AttachTermDebug(<f-args>)
"}}}

" Command: DebugRestart {{{
"
" The 'DebugRestart' command reloads and restarts the application from within a
" debugging session. Useful when attaching/running and wanting to start again
" after rebuilding.
"
" Example:
" :DebugProfile OrdSvr@dev-vm
" :DebugRestart
"
" Example:
" :DebugProfileWrite OrdSvr@dev-vm
"                 \ '$BUILD_ROOT/debug64/bin/emma_OrdSvr'
"                 \ 'emma_tst@ukwok-pc458'
"                 \ '/opt/rh/devtoolset-2/usr/bin/gdbserver'
"                 \ '$CASE/site-specific/bin64/emma_OrdSvr -c emma_OrdSvr.1.cfg'
"                 \ 'ExecTclProc -notrace Fid_ProcessRunning EMMA_ORDSVR_1' 
" :DebugProfile OrdSvr@dev-vm
" :DebugAtach 0
" :DebugRestart
command! -nargs=* DebugRestart 
            \ call remotedebug#Restart(<f-args>)
"}}}


" Command: DebugReset {{{
"
" The 'DebugReset' command closes down pyclewn
"
command! -nargs=0 DebugReset call remotedebug#Reset()
"}}}

" Basic vim plugin boilerplate {{{
call s:restore_cpo()
"  vim:tw=80:ts=8:sw=4:foldmethod=marker
"}}}
