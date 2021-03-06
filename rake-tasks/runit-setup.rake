require 'rake'

namespace :runit do
    desc "Create app-level runsvdir."
    task :create_runsvdir, :app_runsvdir_dir, :app_services_dir, :app_user, :app_group do |t,args|
        # asserts...

        # clean up paths
        args = args.to_hash # Rake::TaskArguments is oddly immutable but with no errors
        [:app_runsvdir_dir, :app_services_dir].each do |sym|
            args[sym] = File.expand_path(args[sym])
        end

        # create "service" which is actually going to be a runsvdir to monitor another directory
        FileUtils.mkdir_p args[:app_runsvdir_dir]

        # runsvdir run script
        File.open("#{args[:app_runsvdir_dir]}/run", 'w') do |f|
          f.write <<-eos
#!/bin/sh
exec 2>&1
exec chpst -u #{args[:app_user]}:#{args[:app_group]} runsvdir #{args[:app_services_dir]} 'log: ...........................................................................................................................................................................................................................................................................................................................................................................................................'
            eos
        end
        File.chmod(0750, "#{args[:app_runsvdir_dir]}/run")

        # runsvdir finish script -- to kill all supervised services
        File.open("#{args[:app_runsvdir_dir]}/finish", 'w') do |f|
          f.write <<-eos
#!/bin/sh
find #{args[:app_services_dir]} -mindepth 1 -maxdepth 1 -type d -print | xargs sv exit
            eos
        end
        File.chmod(0750, "#{args[:app_runsvdir_dir]}/finish")
    end

    desc "Install app-level runsvdir as a system service. Requires root."
    task :install_runsvdir, :app_name, :app_runsvdir_dir, :system_services_dir do |t,args|
        # clean up paths
        args = args.to_hash # Rake::TaskArguments is oddly immutable but with no errors
        [:app_runsvdir_dir, :system_services_dir].each do |sym|
            args[sym] = File.expand_path(args[sym])
        end

        if !File.exists? "#{args[:system_services_dir]}/#{args[:app_name]}"
            begin
                File.symlink("#{args[:app_runsvdir_dir]}", "#{args[:system_services_dir]}/#{args[:app_name]}")
            rescue
                puts "couldn't install #{args[:app_runsvdir_dir]} runsvdir symlink (#{args[:app_runsvdir_dir]} => #{args[:system_services_dir]}/#{args[:app_name]})."
            end
        end
    end
end
