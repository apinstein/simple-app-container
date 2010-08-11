Capistrano::Configuration.instance(true).load do
    set :sac_dir, "sac"
    set(:sac_user) { application.sub(/[^A-Za-z0-9_]/, '') }
    set(:sac_group) { "#{sac_user}_web" }

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
                run "mkdir -p #{deploy_to}/#{sac_dir}"

                # shove an empty rakefile so that we can run sac rake tasks on the server (used to set up sac)
                put "require 'rake'\n", "#{deploy_to}/Rakefile"
                # copy rakefiles
                rake_tasks = File.dirname(__FILE__)  + "/rake-tasks"
                upload rake_tasks, "#{deploy_to}/#{sac_dir}", { :via => :scp, :recursive => true }
            end

            desc "Set up users and groups for this application."
            task :usersAndGroups do
                sac_rake("'usermgmt:user:add[#{sac_user}]'", { :sudo => true })
                sac_rake("'usermgmt:group:add[#{sac_group}]'", { :sudo => true })
                sac_rake("'usermgmt:group:addUser[#{sac_group},#{sac_user}]'", { :sudo => true })
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
end
