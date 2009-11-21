require 'rake'

# NOTE: this isn't tested yet; just copied out and cleaned up from another place where it worked

########### EXPECTED CONFIG VARS ############
# appUser = myapp
# appGroup = myappWeb
# runit_system_service_dir => typically /service
# runit_app_runsvdir_service_install_location => typically /root/user-services
# runit_app_services => typically ~/service
###########################################

namespace :app_container do
    desc "Setup runit services"
    task :setup_runit do
        puts "Creating and installing app-level runit service directory. (requires root)"

        appRunsvrdirName = "#{config['appUser']}-runsvdir"
        appRunsvrdir = "#{config['runit_app_runsvdir_service_install_location']}/#{appRunsvrdirName}"
        FileUtils.mkdir_p appRunsvrdir

        # runner
        File.open("#{appRunsvrdir}/run", 'w') do |f|
          f.write <<-eos
#!/bin/sh
exec 2>&1
exec chpst -u #{config['appUser']}:#{config['appGroup']} runsvdir #{config['runit_app_services']} 'log: ...........................................................................................................................................................................................................................................................................................................................................................................................................'
            eos
        end
        File.chmod(0750, "#{appRunsvrdir}/run")

        # finish script -- to kill all local services
        File.open("#{appRunsvrdir}/finish", 'w') do |f|
          f.write <<-eos
#!/bin/sh
find #{config['runit_app_services']} -mindepth 1 -maxdepth 1 -type d -print | xargs sv exit
            eos
        end
        File.chmod(0750, "#{appRunsvrdir}/finish")
        
        puts "Symlinking app-level runsvdir: #{appRunsvrdir} => #{config['runit_system_service_dir']}"
        if !File.exists? "#{config['runit_system_service_dir']}/#{appRunsvrdirName}"
            begin
                File.symlink("#{appRunsvrdir}", "#{config['runit_system_service_dir']}")
            rescue
                puts "couldn't install #{config['appUser']} runsvdir symlink."
            end
        end
    end
end
