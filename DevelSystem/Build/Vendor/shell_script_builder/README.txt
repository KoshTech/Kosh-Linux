ShellScriptBuilder
    by Ezra Zygmuntowicz

== DESCRIPTION:
  
This is a Builder type of object for defining bash shell scripts
in ruby syntax. Originally made to use in Capistrano Recipes. 
ShellScriptBuilder makes it so you don't have to remember all the 
flags to bash's if statements. It also makes it so you don't have to
worry about proper shell escaping and other things that get munged
by capistrano on deployments.

== SYNOPSYS:

require 'shell_script_builder'

script = shell do |sh|
  sh.sudo.ln_nsf "foo/bar", "bar/bar"

  sh.echo "some string" => "/path/to/log.txt"

  sh.if :directory? => "some/dir" do |sub|
    sub.rm_rf 'some/dir'
    sub.ln_nsf "shared/foo", "some/dir"
    sub.if_not :file? => 'foo' do |ssub|
      ssub.mkdir_p "some/foo"
    end  
  end

  sh.unless :file? => 'foo/bario' do |sub|
    sub.touch 'foo/bario'
  end

  sh.if :writable? => "some/file.txt" do |sub|
    sub.echo "#{time}" => 'some/file.txt'
  end  
  sh.mkdir_p 'foo/bar'
  sh.rm_rf 'foo/bar'
end

puts script

== OUTPUT:

sudo ln -nsf foo/bar bar/bar
echo "some string" >> /path/to/log.txt
if [ -d some/dir ]
  then
    rm -rf some/dir
    ln -nsf shared/foo some/dir
    if [ ! -a foo ]
      then
        mkdir -p some/foo
    fi
fi
if [ ! -a foo/bario ]
  then
    touch foo/bario
fi
if [ -w some/file.txt ]
  then
    echo "#{time}" >> some/file.txt
fi
mkdir -p foo/bar
rm -rf foo/bar



== REQUIREMENTS:

* FIX (list of requirements)

== INSTALL:

$ rake package
$ sudo gem install pkg/shell-script-builder-1.0.0.gem

== LICENSE:

(The MIT License)

Copyright (c) 2007 Ezra Zygmuntowicz

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
'Software'), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
