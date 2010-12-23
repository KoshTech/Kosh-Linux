class BlankSlate
  instance_methods.each { |m| undef_method m unless m =~ /^__|class/ }
end

module Kernel
  def shell
    "#!/bin/bash\n\n"+yield(ShellScriptBuilder.new)
  end
end

class ShellScriptBuilderIfConditionError < RuntimeError;end

class ShellScriptBuilder < BlankSlate
  
  attr_reader :nesting, :cmdbuff
  
  VERSION = '1.0.0'
  
  IF_TESTS = {
    :file?       => '-a',
    :directory?  => '-d',
    :executable? => '-x',
    :writable?   => '-w',
    :symlink?    => '-h',
    :readable?   => '-r'
  }
  
  def initialize(nesting='')
    @nesting = nesting
    @cmdbuff = ""
  end
  
  def method_missing(sym,*args,&blk)
    case m = sym.id2name
    when /^[A-Z]+/
      handle_env_var(m,args[0])
    when /(.*)_(.*)/
      __send__($1,'-'+$2,*args)
    else
      @cmdbuff << "#{@nesting}#{sym} #{args.join(' ')}\n"
    end    
  end
  
  def handle_env_var(var, value)
    @cmdbuff << "#{@nesting}#{var}=#{value} "
    self
  end
  
  def sudo
    @cmdbuff << "#{@nesting}sudo "
    self
  end
  
  def echo(input)
    if Hash === input
      @cmdbuff << "#{@nesting}echo \"#{input.keys.first}\" >> #{input.values.first}\n"
    else
      @cmdbuff << "#{@nesting}echo #{input}\n"
    end  
  end
  
  def to_s
    @cmdbuff
  end
  alias_method :inspect, :to_s
  
  def <<(str)
    @cmdbuff << "#{@nesting}#{str}\n"
  end  
  
  def if(cond, body='')
    body = yield(self.class.new(@nesting+'    ')) if block_given?
    _build_if(cond, body)  
  end
  
  def if_not(cond, body='')
    body = yield(self.class.new(@nesting+'    ')) if block_given?
    _build_if(cond, body, true)
  end
  alias_method :unless, :if_not 
  
  def _build_if(cond, body, negate=false)
    case cond
    when String 
      @cmdbuff << %{#{@nesting}if [ #{negate ? '! ' : ''}#{cond} ]\n  #{@nesting}then\n#{body}#{@nesting}fi\n}
    when Hash
      @cmdbuff << %{#{@nesting}if [ #{negate ? '! ' : ''}#{IF_TESTS[cond.keys.first]} #{cond.values.first} ]\n  #{@nesting}then\n#{body}#{@nesting}fi\n}
    else
      raise ShellScriptBuilderIfConditionError, "the condition for an if statement must be a string or a hash"
    end
  end  
  
end
