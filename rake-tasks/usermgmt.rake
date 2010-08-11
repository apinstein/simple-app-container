# vim: set expandtab tabstop=2 shiftwidth=2:
# Author: Alan Pinstein <apinstein@mac.com>

require 'rake'

namespace :usermgmt do
  namespace :user do
    desc "Create a user"
    task :add, :userName do |t,args|
     addUserIdempotent(args.userName)
    end

    desc "Delete a user"
    task :delete, :userName do |t,args|
     getUserManagementService().deleteUser(args.userName)
    end

    def addUserIdempotent(userName)
      s = getUserManagementService()
      existingUid = s.userId(userName)
      if !existingUid
        s.addUser(userName)
      else
        puts "user #{userName} already exists"
      end
    end
  end

  namespace :group do
    desc "Create a group"
    task :add, :groupName do |t,args|
      addGroupIdempotent(args.groupName)
    end

    desc "Delete a group"
    task :delete, :groupName do |t,args|
     getUserManagementService().deleteGroup(args.groupName)
    end

    desc "Add a user to a group"
    task :addUser, [:groupName,:userName] do |t,args|
     addGroupMembershipIdempotent(args.groupName, args.userName)
    end

    def addGroupIdempotent(groupName)
      s = getUserManagementService()
      existingGid = s.groupId(groupName)
      if !existingGid
        s.addGroup(groupName)
      else
        puts "group #{groupName} already exists"
      end
    end

    def addGroupMembershipIdempotent(groupName, userName)
      s = getUserManagementService()
      if !s.userBelongsToGroup?(groupName, userName)
        s.addGroupMembership(groupName, userName)
      else
        puts "user #{userName} already belongs to group #{groupName}"
      end
    end
  end

  def getUserManagementService
    # switch on RUBY_PLATFORM or something else?
    case RUBY_PLATFORM
    when /darwin/
      return UserManagement_MacOSX.new
    when /linux/
      return UserManagement_linux.new
    end
    raise "Platform " + RUBY_PLATFORM + " not yet implemented."
  end
end

class UserManagement_MacOSX
  def addUser(userName, opts = {})
    opts = {
      :password   => '*',
      :realName   => userName,
      :home       => '/dev/null',
      :shell      => '/dev/null',
    }.merge(opts)

    # create user
    uid = nextUID()
    sh "sudo dscl . create /Users/#{userName} UniqueID #{uid}"
    sh "sudo dscl . create /Users/#{userName} Password \"#{opts[:password]}\""
    sh "sudo dscl . create /Users/#{userName} RealName \"#{opts[:realName]}\""
    sh "sudo dscl . create /Users/#{userName} NFSHomeDirectory \"#{opts[:home]}\""
    sh "sudo dscl . create /Users/#{userName} UserShell \"#{opts[:shell]}\""

    # create user/group
    gid=groupId(userName)
    if !gid
      gid = addGroup(userName)
    end
    # wire group
    sh "sudo dscl . create /Users/#{userName} PrimaryGroupID #{gid}"
    sh "sudo dscl . create /Groups/#{userName} GroupMembership #{userName}"
  end

  def deleteUser(userName)
    # note that the trailing / on /Users is super-important! Prevents deleting all users in case that userName is empty
    sh "sudo dscl . delete /Users/#{userName}"
    deleteGroup(userName)
  end

  def userId(userName)
    begin
      gidInfo=`dscacheutil -q user -a name #{userName} | grep uid`
      gidInfo.match(/uid: *([0-9]+)$/)[1]
    rescue
      nil
    end
  end

  def addGroup(groupName)
    gid=nextGID()
    sh "sudo dscl . create /Groups/#{groupName}"
    sh "sudo dscl . create /Groups/#{groupName} PrimaryGroupID #{gid}"
    sh "sudo dscl . create /Groups/#{groupName} RealName \"#{groupName}\""
    gid
  end

  def addGroupMembership(groupName, userName)
    raise "Group #{groupName} doesn't exit." if !groupId(groupName)
    raise "User #{userName} doesn't exit." if !userId(userName)
    sh "sudo dscl . append /Groups/#{groupName} GroupMembership #{userName}"
  end

  def userBelongsToGroup?(groupName, userName)
    begin
      sh "groups #{userName} | grep #{groupName}"
      true
    rescue
      false
    end
  end

  def deleteGroup(groupName)
    # note that the trailing / on /Groups is super-important! Prevents deleting all groups in case that groupName is empty
    sh "sudo dscl . delete /Groups/#{groupName}"
  end

  def groupId(groupName)
    begin
      gidInfo=`dscacheutil -q group -a name #{groupName} | grep gid`
      gidInfo.match(/gid: *([0-9]+)$/)[1]
    rescue
      nil
    end
  end

  private
  def nextGID()
    maxGID=`dscl . -list /Groups PrimaryGroupID | awk '{print $2}' | sort -rn | head -1`
    maxGID.to_i + 1
  end

  def nextUID()
    maxUID=`dscl . -list /Users UniqueID | awk '{print $2}' | sort -rn | head -1`
    maxUID.to_i + 1
  end
end

class UserManagement_linux
  def addUser(userName, opts = {})
    opts = {
      :password   => '*',
      :realName   => userName,
      :home       => '/dev/null',
      :shell      => '/dev/null',
    }.merge(opts)

    # create user
    sh "/usr/sbin/useradd --home-dir \"#{opts[:home]}\" --shell \"#{opts[:shell]}\" #{userName}"
    # group created automatically
  end

  def deleteUser(userName)
    sh "/usr/sbin/userdel #{userName}"
    # group deleted automatically
  end

  def userId(userName)
    begin
      uidInfo=`grep #{userName} /etc/passwd | cut -d ':' -f3`
      uidInfo.match(/^([0-9]+)$/)[1]
    rescue
      nil
    end
  end

  def addGroup(groupName)
    sh "/usr/sbin/groupadd #{groupName}"
    gid = groupId(groupName)
  end

  def addGroupMembership(groupName, userName)
    raise "Group #{groupName} doesn't exit." if !groupId(groupName)
    raise "User #{userName} doesn't exit." if !userId(userName)
    sh "/usr/sbin/useradd -G #{groupName} #{userName}"
  end

  def userBelongsToGroup?(groupName, userName)
    begin
      sh "groups #{userName} | grep #{groupName}"
      true
    rescue
      false
    end
  end

  def deleteGroup(groupName)
    sh "/usr/sbin/groupdel #{groupName}"
  end

  def groupId(groupName)
    begin
      gidInfo=`grep '^#{groupName}\\>' /etc/group | cut -d ':' -f 3`
      gidInfo.match(/^([0-9]+)$/)[1]
    rescue
      nil
    end
  end
end
