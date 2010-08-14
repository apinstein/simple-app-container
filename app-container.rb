Capistrano::Configuration.instance(true).load do
    # configuration defaults
    set :sac_dir,                       "sac"
    set :sac_enable,                    [
                                            :usersAndGroups,
                                            :runit,
                                            :crontab
                                        ]
    set(:sac_user)                      { application.sub(/[^A-Za-z0-9_]/, '') }
    set(:sac_group)                     { "#{sac_user}_web" }
    set(:sac_app_conf_dir)              { "#{deploy_to}/current/conf" }
    set(:sac_crontab)                   { "#{sac_app_conf_dir}/crontab" }

    # auto-set cap configutation opinions
    set(:user)                          { sac_user }

    # wire into deploy
    before "deploy:setup",          "sac:setup:wire"
    before "deploy:setup",          "sac:setup:init"
    before "deploy:restart",        "sac:restart:wire"

    # special hook - not sure best place to put this atm
    after  "sac:setup:usersAndGroups",  "sac:setup:addMySshKey"
    after  "sac:setup:addMySshKey",     "sac:setup:seedRepositoryHost"

    namespace :sac do
        namespace :setup do
            desc "Install setup hooks"
            task :wire do
                sac_enable.each do |plugin|
                    setupTask = plugin.to_s
                    find_task(setupTask) && after("sac:setup:init", "sac:setup:#{setupTask}")
                end
            end

            desc "Create the directory to contain the application and configure it for SAC management."
            task :init do
                # create container dir for our app
                as_admin do 
                    run "mkdir -p #{deploy_to}/#{sac_dir}"

                    # shove an empty rakefile so that we can run sac rake tasks on the server (used to set up sac)
                    put "require 'rake'\n", "#{deploy_to}/Rakefile", { :via => :scp }
                    # copy rake tasks
                    rake_tasks = File.dirname(__FILE__)  + "/rake-tasks"
                    upload rake_tasks, "#{deploy_to}/#{sac_dir}", { :via => :scp, :recursive => true }
                end
            end

            desc "Set up users and groups for this application."
            task :usersAndGroups do
                as_admin do
                    sac_rake("'usermgmt:user:add[#{sac_user}]'", { :sudo => true })
                    sac_rake("'usermgmt:group:add[#{sac_group}]'", { :sudo => true })
                    sac_rake("'usermgmt:group:addUser[#{sac_group},#{sac_user}]'", { :sudo => true })

                    sac_rake("'usermgmt:group:addUser[#{sac_group},#{sac_admin}]'", { :sudo => true })

                    # fix permissions of root directory
                    puts "Changing permission for #{deploy_to} to #{sac_user}:#{sac_group}"
                    run "#{sudo} chown #{sac_user}:#{sac_group} #{deploy_to}"
                    run "#{sudo} chmod 2775 #{deploy_to}"
                end
            end

            desc "Add the current user's ssh key to the authorized_keys file for :sac_user"
            task :addMySshKey do
                only_on_remotes do
                    as_admin do
                        publicKey = `cat ~/.ssh/id_rsa.pub`
                        publicKey.chomp!
                        installKey = false
                        begin
                            run "#{sudo} grep -nc '#{publicKey}' /home/#{sac_user}/.ssh/authorized_keys"
                            puts "Your SSH key is already installed."
                        rescue
                            installKey = true
                        end

                        if installKey
                            puts "Installing your SSH key."
                            uploadedKeyFile = "#{deploy_to}/new_public_key"
                            upload File.expand_path("~/.ssh/id_rsa.pub"), uploadedKeyFile
                            run "#{sudo} mkdir -p ~#{sac_user}/.ssh"
                            run "#{sudo} chown #{sac_user}:#{sac_user} ~#{sac_user}/.ssh"
                            run "#{sudo} chmod 700 ~#{sac_user}/.ssh"
                            run "#{sudo} sh -c 'cat #{uploadedKeyFile} >> ~#{sac_user}/.ssh/authorized_keys'"
                            run "rm #{uploadedKeyFile}"
                        end
                    end
                end
            end

            desc "Seed the known_hosts file with the host key for the repo server"
            task :seedRepositoryHost do
                # initialize the known hosts file for the remote scm
                if scm == :git
                    githost = repository.split(':').first
                    puts "Seeding your known hosts file for repository host: #{githost}"
                    begin
                        run "ssh -o StrictHostKeyChecking=no #{githost}"
                    rescue
                    end
                end
            end

            desc "Set up runit"
            task :runit do
                runit_config = fetch(:sac_runit_config, {})
                runit_config[:app_runsvdir_dir]     ||= "#{sac_dir}/runsvdir"
                runit_config[:app_services_dir]     ||= "#{deploy_to}/current/service"
                runit_config[:app_user]             ||= sac_user
                runit_config[:app_group]            ||= sac_group
                runit_config[:system_services_dir]  ||= "/service"

                as_admin do
                    # why does this recurse infitely?
                    sac_rake("'runit:create_runsvdir[#{runit_config[:app_runsvdir_dir]},#{runit_config[:app_services_dir]},#{runit_config[:app_user]},#{runit_config[:app_group]}]'", {})
                    sac_rake("'runit:install_runsvdir[#{application},#{runit_config[:app_runsvdir_dir]},#{runit_config[:system_services_dir]}]'", { :sudo => true })
                end
            end
        end

        namespace :restart do
            desc "Install restart hooks"
            task :wire do
                sac_enable.each do |plugin|
                    restartTask = plugin.to_s
                    find_task(restartTask) && after("deploy:restart", "sac:restart:#{restartTask}")
                end
            end

            desc "Reload crontab"
            task :crontab do
                crontab = fetch(:sac_crontab, nil)
                if crontab
                    puts "Reloading crontab for #{sac_user}."
                    if user != sac_user
                        sac_run("crontab -u #{sac_user} #{crontab}", { :sudo => true } )
                    else
                        sac_run("crontab #{crontab}")
                    end
                end
            end
        end
    end

    # runs the specified rake command on the appropriate box (if "local" runs locally, o/w runs on remote)
    # options:
    #   :sudo => true|false
    def sac_rake(command, options)
        if stage == :local
            rakelibdir = File.dirname(__FILE__) + "/rake-tasks"

            command = "rake -R #{rakelibdir} #{command}"
            command = "sudo #{command}" if options[:sudo]

            puts command # we print b/c system doesn't
            system(command)
        else
            rakelibdir = "#{deploy_to}/#{sac_dir}/rake-tasks"

            command = "cd #{deploy_to} && " + (options[:sudo] ? sudo : "") + " rake -R #{rakelibdir} #{command}"
            run command
        end
    end

    def sac_run(command, options = {})
        if stage == :local
            command = "sudo #{command}" if options[:sudo]
            system(command)
        else
            command = "#{sudo} #{command}" if options[:sudo]
            run command
        end
    end

    def sac_admin()
        fetch(:admin_runner, nil)
    end

    # user-hacking from http://www.pgrs.net/2008/8/6/switching-users-during-a-capistrano-deploy
    def as_admin()
      old_user, old_pass = user, password
      close_sessions
      set :user, sac_admin()
      yield
      set :user, old_user
      set :password, old_pass
      close_sessions
    end

    def only_on_remotes()
        if stage != :local
            yield
        end
    end

    def close_sessions
      sessions.values.each { |session| session.close }
      sessions.clear
    end

    def mkdir_p(dir, opts)
        opts ||= {}
        opts[:user]     ||= nil
        opts[:group]    ||= nil
        opts[:mode]     ||= nil
        opts[:sudo]     ||= false

        puts dir + opts.inspect

        localSudo = opts[:sudo] ? sudo : ""

        cmds = []
        if opts[:mode]
            cmds.push " chmod #{opts[:mode]} #{dir} "
        end
        if opts[:user] || opts[:group]
            userCmd = " chown "
            if opts[:user]
                userCmd += "#{opts[:user]}"
            end
            if opts[:group]
                userCmd += ":#{opts[:group]}"
            end
            userCmd += " #{dir}"
            cmds.push userCmd
        end
        mkdirCommand = "[ -d #{dir} ] || #{localSudo} mkdir -p #{dir} "
        if cmds.length
            mkdirCommand += ("\n && #{localSudo}" + cmds.join("\n && #{localSudo} "))
        end
        run mkdirCommand
    end
end
