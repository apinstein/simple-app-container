Capistrano::Configuration.instance(true).load do
    set :sac_dir, "sac"

    namespace :sac do
        namespace :setup do
            desc "Create the directory to contain the application and configure it for SAC management."
            task :bootstrap_dir do
                run "mkdir -p #{deploy_to}"
                run "mkdir -p #{deploy_to}/#{sac_dir}"
                sac_rakefile = <<-RAKEFILE
require 'rake'

FileList["#{deploy_to}/#{sac_dir}/rake-tasks/*.rake"].each do |taskFile|
    load taskFile
end
RAKEFILE
                #put sac_rakefile, "#{deploy_to}/Rakefile"

                rake_tasks = File.dirname(__FILE__)  + "/rake-tasks"
                upload rake_tasks, "#{deploy_to}/#{sac_dir}/rake-tasks", { :via => :scp, :recursive => true }
            end

            desc "Set up users and groups for this application."
            task :usersAndGroups do
                sac_rake("'usermgmt:user:add[foo]'", { :sudo => true })
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
