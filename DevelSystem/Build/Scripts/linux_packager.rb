require 'net/http'
require 'md5'
require 'fileutils'
open_uri_folder = RUBY_VERSION[0,3] == '1.8' ? 'ruby-1.8/' : ''
require "#{open_uri_folder}open-uri"

class Packager
  attr_accessor :config, :options
  private_class_method :new
  @@packager = nil

  def Packager.create
    @@packager = new unless @@packager
    @@packager
  end

  def initialize
    @config = Config.create
    @packages = @config.profile_settings['packages']
    @spinner_thr = nil
    @spinner = false
    @folders_for_clear = Array.new
  end

  def build_all
    if @options[:paco]
      @package = load_package('tools-paco')
      build_package(@package)
    end
    @packages.each do | file_name |
      @package = load_package(file_name)
      build_package(@package) unless optional_package?
    end
  end

  def build_packages(package_list)
    recipes = package_list.split(',')
    recipes.each do |recipe|
      @package = load_package(recipe)
      puts "Building package: #{recipe.green}".dark_green unless optional_package?
      build_package(@package) unless optional_package?
    end
  end
  
  # Check if Recipe is Optional, This is a feature 
  def optional_package?
    optional=false
    if @package['info'].include?('optional')
      optional=true
      case options[:optional]
      when 'auto'
        optional = true  if @package['info']['optional'] == true
        optional = false if @package['info']['optional'] == 'recommended'
        optional = false if @package['info']['optional'] == false
      when 'no'
        if @package['info']['optional'] == false
          optional = false
        else
          optional = true
        end
      when 'yes'
        optional = false
      end
    end
    return optional
  end

  # Check if Action is Optional for Recipe
  def optional_action?(action)
    optional=false
    optional_action=@package[action].nil? ? [] : @package[action]
    if optional_action.include?('optional')
      optional=true
      case options[:optional]
      when 'no'
        if optional_action['optional'] == false
          optional = false
        else
          optional = true
        end
      when 'yes'
        optional = false
      else
        optional = true  if optional_action['optional'] == true
        optional = false if optional_action['optional'] == 'recommended'
        optional = false if optional_action['optional'] == false
      end
    end
    return optional
  end

  # Check if hook is Optional for Recipe
  def optional_hook?(action, hook)
    optional=false
    optional_hook=@package[action][hook].nil? ? [] : @package[action][hook] unless @package[action].nil?
    optional_hook=[] if optional_hook.nil?
    if optional_hook.include?('optional')
      optional=true
      case options[:optional]
      when 'no'
        if optional_hook['optional'] == false
          optional = false
        else
          optional = true
        end
      when 'yes'
        optional = false
      else
        optional = true  if optional_hook['optional'] == true
        optional = false if optional_hook['optional'] == 'recommended'
        optional = false if optional_hook['optional'] == false
      end
    end
    return optional
  end

  def build_package(package, operation="run")
    if operation == 'run' and package_status(package) and not @options[:force_rebuild]
      printf("%s %s %s\n", "*=> Package".dark_blue, package['name'].dark_green, "already built".dark_blue)
      return true
    end

    fetch_file(package) unless optional_action?('fetch')

    hook_package('unpack', 'pre', package) unless optional_hook?('fetch','pre')
    unless package['unpack'].nil?
      unpack_file(package) unless package['unpack']['do'] == false
    else
      unpack_file(package)
    end unless optional_action?('unpack')
    hook_package('unpack', 'post', package) unless optional_hook?('unpack','post')

    hook_package('patch', 'pre', package) unless optional_hook?('patch','pre')
    patch_package(package) unless optional_action?('patch')
    hook_package('patch', 'post', package) unless optional_hook?('patch','post')

    unless package['dependencies'] == false
      check_dependencies(package) unless optional_action?('dependencies')
    end

    if operation == "build" || operation == "run"
      hook_package('configure', 'pre', package) unless optional_hook?('configure','pre')
      configure_package(package) unless optional_action?('configure')
      hook_package('configure', 'post', package) unless optional_hook?('configure','post')

      hook_package('make', 'pre', package) unless optional_hook?('make','pre')
      make_package(package) unless optional_action?('make')
      hook_package('make', 'post', package) unless optional_hook?('make','post')
    end

    unless operation=="source_only"
      hook_package('make_install', 'pre', package) unless optional_hook?('make_install','pre')
      make_install_package(package) unless optional_action?('make_install')
      hook_package('make_install', 'post', package) unless optional_hook?('make_install','post')
      if @options[:paco] and not package['name'] == 'tools-paco'
        command = %Q! PACOLIST=$(paco -afz); time find #{KoshLinux::WORK}/tools -path #{KoshLinux::WORK}/tools/paco -prune -or -print | while read name; do if [ -z "$(echo "$PACOLIST" | grep $name)" ]; then echo $name; fi; done | paco -lp+ #{@package['name']} !
#        command = %Q! find #{KoshLinux::WORK}/tools -path #{KoshLinux::WORK}/tools/paco -prune -or -print | while read name; do [ -z "$(file $name|grep \"$name: directory\")" ] && [ -z "$(paco -q $name | cut -d : -f 2)" ] && echo $name; done | paco -lp+ #{@package['name']} !
        log_name = "paco_#{package['name']}"
        puts "Paco command: #{command}"
        environment_box(command, log_name)
      end
    end
    clear_package(package, operation) unless optional_action?('clear')
    package_status(package, 'ok', 'Package built!')
    exit if options[:stop_one] && operation == 'run'
  end

  def check_dependencies(source_package)
    puts "*=> Checking Dependency for: #{source_package['info']['name']} ".blue
    puts "*==> Recipe Dependencies: #{source_package['dependencies'].inspect}".dark_green unless source_package['dependencies'].nil?
    real_package = @package
    source_package['dependencies']['build'].each do |dependency|
      package = load_package(dependency)
      @package = package
      puts "*==> Dependency->Build: #{package['info']['name']} ".blue
      build_package(@package, "build")
      puts "*==> Dependency->Build->END: #{package['info']['name']}".blue
    end unless source_package['dependencies'].nil? || source_package['dependencies']['build'].nil?

    source_package['dependencies']['source_only'].each do |dependency|
      package = load_package(dependency)
      @package = package
      puts "*==> Dependency->Build: #{package['info']['name']} ".blue
      build_package(@package, "source_only")
      puts "*==> Dependency->Build->END: #{package['info']['name']}".blue
    end unless source_package['dependencies'].nil? || source_package['dependencies']['source_only'].nil?
    @package=real_package
    puts "*=> Dependencies for #{source_package['info']['name']} ".blue + "Done.".dark_green
  end

  def pack_unpack_folder(package)
    if package['info']['unpack_folder'].nil?
      unpack_folder = package['info']['pack_folder']
    else
      unpack_folder = package['info']['unpack_folder']
    end
  end

  def configure_package(package)
    unpack_folder = pack_unpack_folder(package)
    unpack_path = "#{KoshLinux::WORK}/#{unpack_folder}"
    compile_folder = package['info']['compile_folder']
    compile_path = "#{KoshLinux::WORK}/#{compile_folder}"
    unless package['configure'].nil?
      configure_do = package['configure']['do'].nil? ? true : package['configure']['do']
      configure_prefix = package['configure']['prefix'].nil? ? true : package['configure']['prefix']
      return if configure_do === false
      options = package['configure']['options']
      variables = package['configure']['variables']
      variables += " " unless variables.nil?
    else
      configure_do = true
      configure_prefix = true
    end

    unless compile_folder.nil?
      cd_path = "cd #{compile_path}\n"
      compile_path = "../#{unpack_folder}"
      puts "*=> configure_package: compile_path:{#{compile_path}} with unpack_folder:{#{unpack_path}}"
    else
      cd_path = "cd #{unpack_path}\n"
      puts "*=> configure_package: running on unpack_path:{#{unpack_path}} with ."
      compile_path = "."
    end

    if configure_prefix
      prefix = "--prefix=$TOOLS"
    elsif configure_prefix != false
      prefix = configure_prefix
    else
      prefix = ""
    end
    log_file = "configure_#{package['name']}"
    configure_cmd = configure_do === true ? "#{compile_path}/configure" : configure_do
    configure_line = "#{cd_path}#{variables}#{configure_cmd} #{prefix} #{options}"
    puts "*==> Output command configure => #{log_file}.{out,err}"
    configure = environment_box(configure_line, log_file)
    abort("*==] Exiting on configure: #{package['name']}") if configure.nil?
    return configure
  end

  def make_package(package)
    unpack_folder = pack_unpack_folder(package)
    unpack_path = "#{KoshLinux::WORK}/#{unpack_folder}"
    compile_folder = package['info']['compile_folder']
    compile_path = "#{KoshLinux::WORK}/#{compile_folder}"

    unless package['make'].nil?
      make_do = package['make']['do'].nil? ? true : package['make']['do']
      return if make_do === false
      options = package['make']['options']
      variables = package['make']['variables']
      variables += " " unless variables.nil?
    else
      make_do = true
    end

    unless compile_folder.nil?
      cd_path = "cd #{compile_path}\n"
      puts "*=> make_package: running on compile_folder: #{compile_path}"
    else
      cd_path = "cd #{unpack_path}\n"
      puts "*=> make_package: running on unpack_folder: #{unpack_path}"
    end

    log_file = "make_#{package['name']}"
    make_cmd = make_do === true ? 'make' : make_do
    make_line = "#{cd_path}#{variables}#{make_cmd} #{options}"
    puts "*==> Output command make => #{log_file}.{out,err}"
    make = environment_box(make_line, log_file)
    abort("*==] Exiting on make: #{package['name']}") if make.nil?
    return make
  end

  def make_install_package(package)
    unpack_folder = pack_unpack_folder(package)
    unpack_path = "#{KoshLinux::WORK}/#{unpack_folder}"
    compile_folder = package['info']['compile_folder']
    compile_path = "#{KoshLinux::WORK}/#{compile_folder}"

    unless package['make_install'].nil?
      make_install_do = package['make_install']['do'].nil? ? true : package['make_install']['do']
      return if make_install_do === false
      options = package['make_install']['options']
      variables = package['make_install']['variables']
      variables += " " unless variables.nil?
    else
      make_install_do = true
    end

    unless compile_folder.nil?
      cd_path = "cd #{compile_path}\n"
      puts "*=> make_install_package: running on compile_folder: #{compile_path}"
    else
      cd_path = "cd #{unpack_path}\n"
      puts "*=> make_install_package: running on unpack_folder: #{unpack_path}"
    end

    log_file = "make_install_#{package['name']}"
    make_install_cmd = make_install_do === true ? "make #{options} install" : "#{make_install_do} #{options} "
    make_install_line = "#{cd_path}#{variables}#{make_install_cmd}"
    puts "*==> Output command make install => #{log_file}.{out,err}"
    make_install = environment_box(make_install_line, log_file)
    abort("*==] Exiting on make_install: #{package['name']}") if make_install.nil?
    return make_install
  end

  def unpack_file(package)
    file_name = package['info']['filename']
    archive_path = "#{KoshLinux::SOURCES}/#{file_name}"
    pack_folder = package['info']['pack_folder']
    pack_path = "#{KoshLinux::WORK}/#{pack_folder}"
    unpack_folder = pack_unpack_folder(package)
    unpack_path = "#{KoshLinux::WORK}/#{unpack_folder}"
    compile_folder = "#{KoshLinux::WORK}/#{package['info']['compile_folder']}"
    packer = package['info']['packer']
    puts "@=> Unpack path: #{unpack_path}"
    if options[:keep_work] && File.exists?(unpack_path)
      puts "@==> Using previously unpacked: #{unpack_path}"
      check_compile_path
      return true
    end
    puts "@==> Unpacking #{file_name}"
    case packer
      when 'tar.bz2' then
        puts "@===> Archive type: tar.bz2"
        unpack_tar_bz2(archive_path)
      when 'tar.gz' then
        puts "@===> Archive type: tar.gz"
        unpack_tar_gz(archive_path)
      else
       abort("@==] Unreconized packer type: #{packer}")
    end
    check_compile_path
    unless pack_folder == unpack_folder
      puts "@===> Renaming file: #{pack_path} => #{unpack_path}"
      FileUtils.cd(KoshLinux::WORK)
      FileUtils.rm_r(unpack_folder) if File.exists?(unpack_folder)
      FileUtils.mv(pack_folder, unpack_folder)
      FileUtils.cd(KoshLinux::KOSH_LINUX_ROOT)
    end
  end

  def unpack_tar_bz2(file_path)
    FileUtils.cd(KoshLinux::WORK)
    system("#{KoshLinux::KOSH_LINUX_ROOT}/Vendor/bar/bar #{file_path} | tar --recursive-unlink -xjUpf -")
    FileUtils.cd(KoshLinux::KOSH_LINUX_ROOT)
  end

  def unpack_tar_gz(file_path)
    FileUtils.cd(KoshLinux::WORK)
    system("#{KoshLinux::KOSH_LINUX_ROOT}/Vendor/bar/bar #{file_path} | tar --recursive-unlink -xzUpf -")
    FileUtils.cd(KoshLinux::KOSH_LINUX_ROOT)
  end

  def check_compile_path
    compile_folder = @package['info']['compile_folder']
    compile_path   = "#{KoshLinux::WORK}/#{compile_folder}"
    unless compile_folder.nil?
      puts "*==> Creating compile folder: #{compile_folder} on: #{compile_path}"
      FileUtils.mkdir_p(compile_path)
    end
  end

  def load_package(file_name)
    file_path = "#{KoshLinux::PACKAGES}/#{file_name}.yml"
    puts " ==> Loading Recipe (#{file_name}) <== ".dark_blue
    package = YAML::load_file(file_path)
    package["name"] = file_name
    return package
  end

  def fetch_file(package)
    hook_package('fetch', 'pre', package)

    file_name = package['info']['filename']
    download_url = package['info']['download']

    if package['fetch'].nil? or (package.include?('fetch') and package['fetch']['do'] === true)
      abort("Error fetching package file.") unless fetch_file_download(download_url, package['info']['md5'], file_name)
    end

    hook_package('fetch', 'post', package)
  end

  def check_for_checksum(file_path, checksum)
    Digest::MD5.hexdigest(File.read(file_path)) == checksum
  end

  def fetch_file_download(url_for_download, checksum, file_name=nil)
    KoshLinux::require_vendor('progressbar', 'ruby-progressbar')
    uri = URI.parse(url_for_download)
    filename = file_name.nil? ? File.basename(uri.path) : file_name
    filepath = "#{KoshLinux::SOURCES}/#{filename}"
    only_url = File.dirname(url_for_download)
    result = nil

    unless File.exist?(filepath) && check_for_checksum(filepath, checksum)
      puts " => Connecting on #{uri.host}, for download the file #{filename}"
      begin
        pbar = nil
        uri.open(:content_length_proc => lambda {|t|
                   if t && 0 < t;
                     puts " => Downloading file #{filename} from #{only_url} "
                     pbar = ProgressBar.new(filename, t)
                     pbar.file_transfer_mode
                   end
                 },
                 :progress_proc => lambda {|s|
                   pbar.set s if pbar
                 }) do |file|
          open(filepath, 'wb') do |archive|
            archive.write(file.read)
            archive.close
            result = filepath
          end
        end
      rescue Errno::ETIMEDOUT
        puts " ==| Timeout error, trying again in few seconds..."
        sleep 3
        result = fetch_file_download(url_for_download, checksum, file_name)
      rescue SocketError
        puts " ==| I got error, is your network up? trying again in few seconds..."
        sleep 5
        result = fetch_file_download(url_for_download, checksum, file_name)
      else
        puts " => Download complete."
      end
    else
      puts " => Skip download, using previously downloaded archive #{file_name}..."
      result = filepath
    end
    return result
  end

  def hook_package(action, hook, package)
    return if package[action].nil?
    current_hook = package[action][hook]
    unless current_hook.nil? || current_hook.empty?
      puts "#{'#'.green}#{'_=> Running hook('.yellow}#{package['name'].dark_blue}::#{action.blue}.#{hook.green}#{')'.yellow}"
      unpack_folder = pack_unpack_folder(package)
      compile_folder = package['info']['compile_folder']
      compile_folder = unpack_folder if compile_folder.nil?
      case action
      when 'unpack', 'patch'
        cd_path = "cd #{KoshLinux::WORK}/#{unpack_folder}\n"
      else
        cd_path = "cd #{KoshLinux::WORK}/#{compile_folder}\n"
      end
      log_file = "#{action}-#{hook}_#{package['name']}"
      result = environment_box(cd_path + current_hook, log_file)
      puts "#{'#'.green}#{'_=> End hook('.yellow}#{action.blue}.#{hook.green}) ==__"
      abort(" -==] Exiting hook(#{package['name']}:#{action}.#{hook})") if result.nil?
    end
  end

  def patch_package(package)
    info = package['info']
    patches = info['patches']
    return if patches.nil?
    options = info['patches_options']
    puts " => Checking for #{patches.count} patch(es)"
    patches.each do |patch|
      patch_info = patch[1]
      filepath = fetch_file_download(patch_info['download'],patch_info['md5'])
      if filepath
        work_folder = "#{KoshLinux::WORK}/#{pack_unpack_folder(package)}"
        cd_path = "cd #{work_folder}\n"
        unless File.exist?(File.join(work_folder, patch[0]))
          options = patch_info['options'] unless patch_info['options'].nil?
          puts " _=> Appling patch: #{patch_info['name']} ==__"
          log_file = "patch_#{package['name']}"
          command_for_patch = "#{cd_path} patch #{options} -i #{filepath} && echo 'patched' >#{patch[0]}"
          result = environment_box(command_for_patch, log_file)
          abort(" _=> Error appling patch (#{package['name']}:#{patch_info['name']})") if result.nil?
        else
          puts " _=> No needed patch: #{patch_info['name']}"
        end
      else
        abort(" _==] Erro with downloading: #{patch_info['name']}")
      end
    end
  end

  def environment
    $HOME = KoshLinux::WORK
    ENV['BUILD'] = KoshLinux::KOSH_LINUX_ROOT
    ENV['WORK']  = KoshLinux::WORK
    ENV['TOOLS'] = KoshLinux::TOOLS
    ENV['LOGS']  = KoshLinux::LOGS
    ENV['PATH']  = "#{'/usr/lib/ccache:' if options[:ccache]}#{KoshLinux::TOOLS}/bin:/bin:/usr/bin"

    environment = %W! HOME='#{$HOME}' BUILD='#{ENV['BUILD']}' WORK='#{ENV['WORK']}' TOOLS='#{ENV['TOOLS']}' LOGS='#{ENV['LOGS']}' PATH='#{ENV['PATH']}' USER='#{ENV['USER']}' !

    file_path = "#{KoshLinux::PROFILES}/LinuxBasic.yml"
    variables = YAML::load( File.open( file_path ))['variables']
    variables.inject("") do |vars, variable|
      ENV[variable[0].upcase] = variable[1]
      environment << "#{variable[0].upcase}='#{variable[1]}'"
    end
    environment
  end

  def console_script
    console_script =<<END_OF_CONSOLE
#!/bin/bash

HOME='#{$HOME}'
exec env -i HOME=\"$HOME\" TERM=$TERM /bin/bash $@

END_OF_CONSOLE
  end

  def environment_set
    debug = "set -x" if @options[:debug]
    extra_options = [
                     "[ ! -z \"$PS1\" ] && PS1=\"`tput setaf 1; tput bold`
[KoshLinux::Console]`tput sgr0` \\u [B]:\\V [J]:\\j [T]:\\l [L]:\\#:\\n\\w(\\$)> \"",
                     "set +h",
                     "umask 022",
                    ]

    # Create and update .bashrc and console files
    @bashrc_path=File.join(KoshLinux::WORK, '.bashrc')
    console_path=File.join(KoshLinux::WORK, 'console')
    begin
      bashrc_file = File.open(@bashrc_path, 'w') do |bashrc|
        extra_options.each do |options|
          bashrc.write("#{options}\n")
        end
        environment.each do |env|
          bashrc.write("export #{env}\n")
        end
      end
      console_file = File.open(console_path, 'w') do |console|
        console.write(console_script)
        console.chmod(0754)
      end
    end
    true
  end

  def variables_package
    unless @package['variables'].nil?
      set_variables=@package['variables']['set'] unless @package['variables']['set'].nil?
      unset_variables=@package['variables']['unset'] unless @package['variables']['unset'].nil?
      set_vars = set_variables.split("\n").collect do |variable|
        variable_and_condition = variable.split(':')
        condition = variable_and_condition[1].to_s+" && " unless variable_and_condition[1].nil?
        condition.to_s + "export " + variable_and_condition[0].to_s
      end unless set_variables.nil?
      unset_vars = unset_variables.split("\n").collect do |variable|
        variable_and_condition = variable.split(':')
        condition = variable_and_condition[1].to_s+" && " unless variable_and_condition[1].nil?
        condition.to_s + "unset " + variable_and_condition[0].to_s
      end unless unset_variables.nil?
    end
    return set_vars, unset_vars
  end

  def environment_box(which_command, log_file)
    KoshLinux::require_vendor('shell_script_builder')
    environment_set
    last_command_path="#{$HOME}/last_command.sh"
    last_command_script=shell do |sh|
      sh.if :file? => @bashrc_path do |bashrc|
        bashrc.source @bashrc_path
      end
      set_vars, unset_vars = variables_package
      set_vars.each do |var|
        sh << var
      end unless set_vars.nil?
      unset_vars.each do |var|
        sh << var
      end unless unset_vars.nil?
      sh.set_x if @options[:debug]
      sh.export if @options[:debug]
      sh.echo "'BEGIN COMMANDS>>>'" if @options[:debug]
      sh << which_command
    end
    File.open(last_command_path, 'w') do |last_command|
      last_command.write(last_command_script)
      last_command.chmod(0754)
    end

    command_line = "#{last_command_path}"
    formated_commands=which_command.split("\n").collect{|line|"# ".green+line.pur+"\n"}.join("  ")
    formated_commands="  "+formated_commands
    full_formated_commands=last_command_script.split("\n").collect{|line|"# ".green+line.pur+"\n"}.join("  ")
    full_formated_commands="  "+full_formated_commands
    puts "#{'#'.green}#{'=> Commands:'.yellow}\n#{formated_commands}" if @options[:debug]
    spinner true
    %x[ exec env -i HOME=$HOME TERM=$TERM /bin/bash #{command_line} 2>#{ENV['LOGS']}/#{log_file}.err 1>#{ENV['LOGS']}/#{log_file}.out ]
    command_status = $?.exitstatus
    spinner false
    status_cmd="#==> Commands exitstatus(#{command_status})"
    unless command_status.nil?
      if command_status > 0
        puts status_cmd.yellow
        puts "#==] Commands was:\n#{full_formated_commands}".red
        result = nil
      else
        puts status_cmd.green
        result = true
      end
    else
      puts status_cmd.red
      puts "#==] Unknown error".red
      result = nil
    end
    result
  end

  def package_status(package, status=nil, message=nil)
    filename=[KoshLinux::WORK,'.status', package['name'] , 'ok'].join('/')
    dirname=File.dirname(filename)
    statusdir=File.dirname(dirname)
    FileUtils.mkdir(statusdir) unless File.exist?(statusdir)
    FileUtils.mkdir(dirname) unless File.exist?(dirname)

    if status.nil?
      return true if File.exist?(filename)
      return false
    end
    case status
    when 'ok' then
      ok_file = File.open(filename,'w').write(message)
      return true
    when 'clear' then
      FileUtils.rm_f(filename)
      return true
    end
  end

  def clear_package(package, operation)
    unpack_folder  = pack_unpack_folder(package)
    compile_folder = package['info']['compile_folder']
    [ unpack_folder, compile_folder ].compact.each do |folder|
      @folders_for_clear << folder
    end
    @folders_for_clear.compact.each do |folder|
      clean_folder = File.join(KoshLinux::WORK, folder)
       if File.exist?(clean_folder)
         puts "*===> Cleaning-up folder used for build package: #{folder}".dark_green
         FileUtils.rm_rf(clean_folder)
       end
    end if operation == "run"
  end

  def spinner(action)
    theme = {
      'chars' => %w{ (| (/ (- (\\ },
      'chars_inv' => %w{ \\) -) /) |) },
      'signs' => %w{ ---------- >--------- ->-------- -->------- --->------ ---->----- ----->---- ------>--- ------->-- -------->- ---------> ---------- ---------< --------<- -------<-- ------<--- -----<---- ----<----- ---<------ --<------- -<-------- <--------- },
    }

    @spinner = action
    @spinner_thr = Thread.new{
      sleep 3
      cursor_off=`tput civis`
      cursor_on =`tput cnorm`
      columns = 76
      columns = ENV['COLUMNS'] unless ENV['COLUMNS'].nil?
      while @spinner
        output = "[pid]:#{Process.pid}[ppid]:#{Process.ppid}#{theme['chars'][0]}#{theme['signs'][0]}#{theme['chars_inv'][0]}#{cursor_off}"
        times = columns - output.size
        times.times do
          output += "\s"
        end

        $stderr.print output
        sleep 0.1
        $stderr.print "\r"
        theme.each do |item|
          item[1].push item[1].shift
        end
      end
      columns.times { $stderr.print "\s" }
      $stderr.print "\r#{cursor_on}"
    } if @spinner_thr.nil? or not @spinner_thr.alive?
    @spinner_thr.join unless @spinner
  end
end
