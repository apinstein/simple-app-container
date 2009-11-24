Capistrano::Configuration.instance(true).load do
    appUser = 'myapp'
    appGroup = 'myapp'
    appGroupWeb = 'myappweb'
    appDirectory = "~/www"

    namespace :appcontainer do
        task :create_user do
            # does user exist?
            userExists = capture("grep #{appUser} /etc/passwd || echo USERDNE").strip
            if userExists == 'USERDNE'
                sudo "/usr/sbin/useradd #{appUser}"
                sudo "/usr/sbin/groupadd -f #{appGroupWeb}"
            end
            homeDir = capture("grep #{appUser} /etc/passwd | cut -d ':' -f 6").strip
            appDirectory = appDirectory.sub('~', homeDir)
            sudo "/bin/mkdir -p #{appDirectory}"
            sudo "chown #{appUser}:#{appGroupWeb} #{appDirectory}"
            sudo "chmod 2775 #{appDirectory}"
        end
    end

    # httpd.conf -symlink to the /etc/httpd/conf/ dir; remove symlink if restart fails
end
