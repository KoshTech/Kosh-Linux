require 'test/unit'
$:.unshift File.dirname(__FILE__) + "/../lib"
require 'shell_script_builder'

def shell
  yield(ShellScriptBuilder.new)
end

class ShellScriptBuilderTest < Test::Unit::TestCase
  
  def setup
    @shb = ShellScriptBuilder.new
  end
  
  def teardown
    @shb = nil
  end
  
  def test_initialize_with_nesting
    assert_equal('', @shb.cmdbuff)
    assert_equal('', @shb.nesting)
    shb = ShellScriptBuilder.new('  ')
    assert_equal('', shb.cmdbuff)
    assert_equal('  ', shb.nesting)
  end
  
  def test_method_missing_no_flags
    @shb.touch "somedir/foo"
    assert_equal("touch somedir/foo\n", @shb.cmdbuff)
    @shb.rm "somedir/foo"
    assert_equal("touch somedir/foo\nrm somedir/foo\n", @shb.cmdbuff)
  end
  
  def test_method_missing_with_flags
    @shb.touch_ac "somedir/foo"
    assert_equal("touch -ac somedir/foo\n", @shb.cmdbuff)
    @shb.rm_rf "somedir/bar"
    assert_equal("touch -ac somedir/foo\nrm -rf somedir/bar\n", @shb.cmdbuff)
    @shb.mkdir_p "bar/foo"
    assert_equal("touch -ac somedir/foo\nrm -rf somedir/bar\nmkdir -p bar/foo\n", @shb.cmdbuff)
  end
  
  def test_simple_String_if_statement
    @shb.if '-a foo/bar' do |sh|
      sh.mkdir_p 'foo/bar2'
    end
    assert_equal("if [ -a foo/bar ]\n  then\n    mkdir -p foo/bar2\nfi\n", @shb.cmdbuff)
    @shb.if '-d foo/bar' do |sh|
      sh.touch 'foo/bar/text'
    end
    assert_equal("if [ -a foo/bar ]\n  then\n    mkdir -p foo/bar2\nfi\nif [ -d foo/bar ]\n  then\n    touch foo/bar/text\nfi\n", @shb.cmdbuff)
    
  end
  
  def test_if_statements_with_hash_flags
    @shb.if :file? => 'foo/bar' do |sh|
      sh.mkdir_p 'foo/bar2'
    end
    assert_equal("if [ -a foo/bar ]\n  then\n    mkdir -p foo/bar2\nfi\n", @shb.cmdbuff)
    @shb.if :directory? => 'foo/bar' do |sh|
      sh.touch 'foo/bar/text'
    end
    assert_equal("if [ -a foo/bar ]\n  then\n    mkdir -p foo/bar2\nfi\nif [ -d foo/bar ]\n  then\n    touch foo/bar/text\nfi\n", @shb.cmdbuff)
  end
  
  def test_append_raw_shell_code
    @shb << "if [ -a foo/bar ]; then curl google.com;fi"
    assert_equal("if [ -a foo/bar ]; then curl google.com;fi\n", @shb.cmdbuff)
  end
  
  def test_nested_if_statements
    @shb.if :file? => 'foo/bar' do |sh|
      sh.mkdir_p 'foo/bar2'
      sh.if :executable? => '/foo/script.sh' do |s|
        s.mkdir_p 'foo/bar/baz'
      end  
    end
    assert_equal("if [ -a foo/bar ]\n  then\n    mkdir -p foo/bar2\n    if [ -x /foo/script.sh ]\n      then\n        mkdir -p foo/bar/baz\n    fi\nfi\n", @shb.cmdbuff)
  end
  
  def test_echo_normal_string
    @shb.echo "hello world!"
    assert_equal("echo hello world!\n", @shb.cmdbuff)
  end
  
  def test_echo_with_hash
    @shb.echo "hello world!" => 'path/to/log.txt'
    assert_equal("echo \"hello world!\" >> path/to/log.txt\n", @shb.cmdbuff)
  end
  
  def test_setting_env_vars
    @shb.RAILS_ENV('production').mkdir_p 'foo/bar'
    assert_equal("RAILS_ENV=production mkdir -p foo/bar\n", @shb.cmdbuff)
  end
  
  def test_complex_example_of_full_dsl
    time = Time.now
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
expected =<<-EOF
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
EOF
    assert_equal(expected, script.to_s)
  end
end