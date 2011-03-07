require 'lockfile'
require 'inifile'
require 'net/ssh'
require 'tmpdir'

module Gitosis
  # server config
  #GITOSIS_URI = 'git@projects-test.cecs.pdx.edu:gitosis-admin.git'
  #GITOSIS_URI = '/www/git/gitosis-admin.git'
  GITOSIS_URI = 'git@projects.cecs.pdx.edu:gitosis-admin.git'
  GITOSIS_BASE_PATH = '/www/git/'
  SUBVERSION_BASE_PATH = 'file:///www/svn/'
  
  # commands
  ENV['GIT_SSH'] = SSH_WITH_IDENTITY_FILE = File.join(RAILS_ROOT, 'vendor/plugins/redmine_gitosis/extra/ssh_with_identity_file.sh')
  
  def self.destroy_repository(project)
  #  path = File.join(GITOSIS_BASE_PATH, "#{project.identifier}.git")
  #  `rm -Rf #{path}`
  end
  
  def self.update_repositories(projects)
    projects = (projects.is_a?(Array) ? projects : [projects])
    
    Lockfile(File.join(Dir.tmpdir,'gitosis_lock'), :retries => 2, :sleep_inc=> 10) do

      # HANDLE GIT

      # create tmp dir
      local_dir = File.join(Dir.tmpdir,"redmine-gitosis-#{Time.now.to_i}")

      Dir.mkdir local_dir

      # clone repo
      ActionController::Base::logger.info "git: git clone #{GITOSIS_URI} #{local_dir}/gitosis 2>&1"
      IO.popen("git clone #{GITOSIS_URI} #{local_dir}/gitosis 2>&1") do |process|
        process.each_line { |line| ActionController::Base::logger.info "git: #{line}" }
      end 
    
      changed = false
    
      projects.select{|p| p.repository.is_a?(Repository::Git)}.each do |project|
        # fetch users
        users = project.member_principals.map(&:user).compact.uniq
        write_users = users.select{ |user| user.allowed_to?( :commit_access, project ) }
        read_users = users.select{ |user| user.allowed_to?( :view_changesets, project ) }
    
        # write key files
        users.map{|u| u.gitosis_public_keys.active}.flatten.compact.uniq.each do |key|
          File.open("#{local_dir}/gitosis/keydir/#{key.identifier}.pub", 'w') {|f| f.write(key.key.gsub(/\n/,'').chomp) }
        end

        # delete inactives
        users.map{|u| u.gitosis_public_keys.inactive}.flatten.compact.uniq.each do |key|
          File.unlink("#{local_dir}/gitosis/keydir/#{key.identifier}.pub") rescue nil
        end
    
        # write config file
        conf = IniFile.new(File.join(local_dir,'gitosis','gitosis.conf'))
        original = conf.clone
        name = "#{project.identifier}"
    
        conf["group #{name}"]['writable'] = name
        conf["group #{name}"]['members'] = write_users.map{|u| u.gitosis_public_keys.active}.flatten.map{ |key| "#{key.identifier}" }.join(' ')
        unless conf.eql?(original)
          conf.write 
          changed = true
        end
      end
    
      if changed
        # add, commit, push, and remove local tmp dir
        dir = Dir.pwd
        Dir.chdir("#{local_dir}/gitosis")
        ActionController::Base::logger.info "git: git add keydir/* gitosis.conf"
        IO.popen("git add keydir/* gitosis.conf") do |process|
          process.each_line { |line| ActionController::Base::logger.info "git: #{line}" }
        end 
        ActionController::Base::logger.info "git: git commit -a -m 'updated by Redmine Gitosis'"
        IO.popen("git commit -a -m 'updated by Redmine Gitosis'") do |process|
          process.each_line { |line| ActionController::Base::logger.info "git: #{line}" }
        end 
        ActionController::Base::logger.info "git: git push"
        IO.popen("git push") do |process|
          process.each_line { |line| ActionController::Base::logger.info "git: #{line}" }
        end 
        Dir.chdir(dir)
      end
    
      # remove local copy
      `rm -Rf #{local_dir}`
          
    end
    
    
  end
  
end
