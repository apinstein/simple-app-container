Capistrano::Configuration.instance(true).load do
    # configuration defaults
    set :sac_dir,                       "sac"
    set(:sac_user)                      { application.sub(/[^A-Za-z0-9_]/, '') }
    set(:sac_group)                     { "#{sac_user}_web" }

    # auto-set cap configutation opinions
    set(:user)                          { sac_user }

    # wire into normal deploy
    before "deploy:setup",          "sac:setup:init"
    after  "sac:setup:init",        "sac:setup:usersAndGroups"
    after  "sac:setup:init",        "sac:setup:runit"

    # wire into restart
    after "deploy:restart",         "sac:restart:runit"

    namespace :sac do
        namespace :setup do
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

                    # install public key
                end
            end

            desc "Set up runit"
            task :runit do
                #sac_rake("'usermgmt:user:add[foo]'", { :sudo => true })
            end
        end

        namespace :restart do
            desc "Restart runit"
            task :runit do
                puts "runit automatically notices new files when the current/ symlink is rewired."
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

            system(command)
        else
            rakelibdir = "#{deploy_to}/#{sac_dir}/rake-tasks"

            command = "cd #{deploy_to} && " + (options[:sudo] ? sudo : nil) + " rake -R #{rakelibdir} #{command}"
            run command
        end
    end

    def sac_admin()
        fetch(:admin_runner, nil)
    end

    # user-hacking from http://www.pgrs.net/2008/8/6/switching-users-during-a-capistrano-deploy
    def as_admin()
      old_user, old_pass = user, password
      set :user, sac_admin()
      close_sessions
      yield
      set :user, old_user
      set :password, old_pass
      close_sessions
    end

    def close_sessions
      sessions.values.each { |session| session.close }
      sessions.clear
    end
end
