# Please view README before using


task :bootstrap => [:environment] do
  %w(database.yml settings.yml).each do |file|
    unless File.exists? File.join(RAILS_ROOT, 'config', file)
      system "cp #{File.join(RAILS_ROOT, 'config', file.gsub('.','.example.'))} #{File.join(RAILS_ROOT, 'config', 'database.yml')}"
    end
  end
end


namespace :server do

  # Load our settings
  task :server_environment => [:environment] do
    deploy_file = File.join(RAILS_ROOT, 'config', 'deploy.yml')
    raise "#{deploy_file} missing" unless File.exists? deploy_file
    settings = YAML::load(File.open(deploy_file))[RAILS_ENV]
    @app_name = settings['app_name']
    @environment = settings['environment'] || RAILS_ENV
    @ssh_cmd = settings['ssh_cmd'] || 'ssh'
    @deploy_to = settings['deploy_to']
    @git_uri = settings['git_uri'] || "~/git/" + @app_name
    @git_repos = settings['git_repos'] || 'master'
    @pretend = settings['pretend'] || false
    @compress_cmd = settings['compress_cmd'] || "zip -9r :dest.zip :src -x ':src/.git/*'"
  end

  # run a command on the server
  def remote_run(lines)
    lines = [lines] unless lines.is_a? Array
    command = @ssh_cmd + ' ' + '"' + lines.join(' && ') + '"'
    puts command
    system command unless @pretend
  end

  # run a rake task on the server
  def remote_task(task)
    remote_run ["cd #{deploy_to}", "rake #{task} RAILS_ENV=#{RAILS_ENV}"]
  end


  # build deploy path
  def deploy_to
    @deploy_to.gsub(':environment', @environment).gsub(':app_name', @app_name)
  end

  desc 'Setup folders and versioning on server'
  task :setup => [:server_environment] do
    remote_run ["mkdir #{deploy_to}", "cd #{deploy_to}", "touch ../#{@app_name}_#{@environment}_last_deploy.txt", "git init", "git remote add origin #{@git_uri}"]
  end

  desc 'Teardown on server'
  task :teardown => [:server_environment] do
    remote_run "mv #{deploy_to} #{deploy_to}/../#{@app_name}_#{@environment}_#{Time.now.strftime('%d%m%Y%H%M%S')}"
  end

  desc 'Backup deployment'
  task :backup => [:server_environment] do
    remote_run @compress_cmd.gsub(':dest', "#{deploy_to}/../#{@app_name}_#{@environment}_#{Time.now.strftime('%d%m%Y%H%M%S')}").gsub(':src', deploy_to)
  end

  desc 'Update code on server with latest from git'
  task :update_code => [:server_environment] do
    remote_run ["cd #{deploy_to}", "git pull origin #{@git_repos}"]
  end

  desc 'Restart application'
  task :restart_app => [:server_environment] do
    remote_run ["touch #{deploy_to}/tmp/restart.txt"]
  end

  desc 'Pull the UI changes in to git'
  task :get_ui => [:server_environment] do
    remote_run ["cd #{deploy_to}", "git add .", "git commit -m 'UI Changes (via FTP)'", "git push"]
    puts "You now need to pull these changes (if any) from git to get them locally"
  end  


  # Run any rake task on the server (eg. rake server:db:create)
  Rake.application.tasks.reject { |task| task.name.include? 'server' or task.name == 'environment'}.each do |task|  
    task task.name.to_sym => [:server_environment] do
      remote_task task.name
    end
  end
  
  task :deploy => [:update_code, :restart_app]
end