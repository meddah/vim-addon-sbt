exec scriptmanager#DefineAndBind('s:c','g:vim_addon_sbt', '{}')
let s:c['mxmlc_default_args'] = get(s:c,'mxmlc_default_args', ['--strict=true'])

" author: Marc Weber <marco-oweber@gxm.de>

" usage example:
" ==============
" requires python!
" map <F2> :exec 'cfile '.sbt#Compile(["mxmlc", "-load-config+=build.xml", "-debug=true", "-incremental=true", "-benchmark=false"])<cr>

" implementation details:
" ========================
" python is used to run a sbt process reused.
" This code is copied and modified. source vim-addon-sbt
" Because Vim is not threadsafe ~compile commands are not supported.
" (There are workaround though)
" You can still use vim-addon-actions to make Vim trigger recompilation
" when you write a file

" TODO implement shutdown, clean up ?
"      support quoting of arguments
fun! sbt#Compile(sbt_command_list)

  let g:sbt_command_list = a:sbt_command_list

  if !has('python')
    throw "python support required to run sbt process"
  endif

python << PYTHONEOF
import sys, tokenize, cStringIO, types, socket, string, vim, os, re
from subprocess import Popen, PIPE

if not globals().has_key('sbtCompiler'):

  # sbt_dict keeps compilation ids
  sbt_dict = {}

  class SBTCompiler():

    def __init__(self):
      self.tmpFile = vim.eval("tempname()")
      self.ids = {}
      # errors are print to stderr. We want to catch them!
      # start interactive mode so that we can recompile without reloading sbt
      p = Popen(["java","-Dsbt.log.noformat=true","-jar",vim.eval('SBT_JAR()')], \
            shell = False, bufsize = 1, stdin = PIPE, stdout = PIPE, stderr = PIPE)

      self.sbt_o = p.stdout
      self.sbt_i = p.stdin

      self.waitForShell(None)
    
    def waitFor(self, pattern, out):
      """ wait until pattern is found in an output line. Write non matching lines to out """

      pat = "Project does not exist, create new project? (y/N/s) "

      allPatterns = [pat, pattern]

      while 1:
        line = self.readLineSkip(allPatterns)

        # hack: forward pat question to user
        if line == pat:
          self.sbt_i.write(vim.eval("input('%s')" % pat)+"\n")
          self.sbt_i.flush()
          continue

        match = re.match(pattern, line)
        if match != None:
          return match
        elif out != None:
          out.write(line+"\n")


    # the input line usually don't end with \n
    # so break on those queries
    # probably this can be implemented more efficiently
    def readLineSkip(self, patterns):
      # copy list:
      l = patterns[:]
      idx = 0
      read = ""

      while len(l) > 0:
        c = self.sbt_o.read(1)
        if c == "\n":
          return read
        else:
          read = read+c

        # remove patterns from list which can no longer match
        for i in range(len(l)-1,-1,-1):
          if l[i][idx] != c:
            # this pattern can no longer match
            l.pop(i)
          else:
            # full match
            if len(l[i]) == idx+1:
              return read
        idx += 1

      line = read + self.sbt_o.readline()
      # remove trailing \n
      return line[:-1]

    def waitForShell(self, out):
      self.waitFor("> ", out)
    
    def sbt(self, args):
      out = open(self.tmpFile, 'w')
      cmd = " ".join(args)

      self.sbt_i.write(cmd+"\n")
      self.sbt_i.flush()
      res = self.waitFor(".*Total time: .*completed.*", out)
      self.waitForShell(out)
      out.close()
      return self.tmpFile

  sbtCompiler = SBTCompiler()

f = sbtCompiler.sbt(vim.eval('g:sbt_command_list'))
vim.command("let g:sbt_result='%s'"%f)

PYTHONEOF

  " unlet g:sbt_command_list
  " unlet g:sbt_result
  return g:sbt_result
endf


fun! sbt#CompileRHS(usePython, args)
  " errorformat taken from http://code.google.com/p/simple-build-tool/wiki/IntegrationSupport
  let ef=
      \  '%E\ %#[error]\ %f:%l:\ %m,%C\ %#[error]\ %p^,%-C%.%#,%Z'
      \.',%W\ %#[warn]\ %f:%l:\ %m,%C\ %#[warn]\ %p^,%-C%.%#,%Z'
  "   \.',%-G%.%#'

  let args = a:args

  " let ef = escape(ef, '"\')
  if !a:usePython
    let args =  ["java", "-Dsbt.log.noformat=true", "-jar", SBT_JAR()] + args
  endif
  let args = actions#ConfirmArgs(args,'sbt command')
  if a:usePython
    let ef = escape(ef, '"\')
    return ['exec "set efm='.ef.'" ',"exec 'cfile '.sbt#Compile(".string(args).")"]
  else
    " use RunQF
    return "call bg#RunQF(".string(args).", 'c', ".string(ef).")"
  endif
endfun
