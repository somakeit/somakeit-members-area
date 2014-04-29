process.env['DISABLE_VALIDATIONS'] = true
process.env.NO_EMAIL = true
MembersArea = require 'members-area'

# Make sure we're in the right folder.
process.chdir __dirname

{orm} = require 'members-area/app/models'
async = require 'members-area/node_modules/async'

friendRoleId = 1
trusteeRoleId = 2
supporterRoleId = 3
memberRoleId = 4

MembersArea.start ->
  orm.connect process.env.DATABASE_URL, (err, db) =>
    require('members-area/app/models') MembersArea, db, (err, models) ->
      q = db.driver.execQuery.bind(db.driver)

      addUser = (oldUser, next) ->
        try
          oldUser.data = JSON.parse oldUser.data
        catch
          oldUser.data = {}
        newUser = new models.User
          email: oldUser.email
          username: oldUser.username
          hashed_password: oldUser.password
          fullname: oldUser.fullname
          address: oldUser.address
          createdAt: oldUser.createdAt
          updatedAt: oldUser.updatedAt
          meta:
            legacy: oldUser.data
            legacyGocardless: oldUser.data.gocardless
            emailVerificationCode: oldUser.data.validationCode
            registeredFromIP: oldUser.data.registeredFromIP
            _payments_paidUntil: oldUser.paidUntil
            rfidcodes: oldUser.data.cards
            # XXX: RFID CODES
        newUser.id = oldUser.id # If we do this above then isNew = false
        newUser.validate = (cb) ->
          process.nextTick cb
        saveUser = (done) ->
          newUser.save done
        makeAdmin = (done) ->
          roleUser = new models.RoleUser
            user_id: newUser.id
            role_id: trusteeRoleId
            approved: oldUser.approved
          roleUser.save done
        makeFriend = (done) ->
          roleUser = new models.RoleUser
            user_id: newUser.id
            role_id: friendRoleId
            approved: oldUser.approved
          roleUser.save done
        makeMember = (done) ->
          roleUser = new models.RoleUser
            user_id: newUser.id
            role_id: memberRoleId
            approved: oldUser.approved
          roleUser.save done
        rejectMember = (done) ->
          roleUser = new models.RoleUser
            user_id: newUser.id
            role_id: memberRoleId
            rejected: oldUser.updatedAt
            meta:
              rejectedBy: oldUser.data.rejectedBy
              rejectionReason: oldUser.data.rejectedReason
          roleUser.save done
        requestFriend = (done) ->
          roleUser = new models.RoleUser
            user_id: newUser.id
            role_id: friendRoleId
          roleUser.save done
        addSocial = (vendor, id, done) ->
          userLinked = new models.UserLinked
            user_id: newUser.id
            type: vendor
            identifier: id
          userLinked.save done
        addFacebook = (done) -> addSocial 'facebook', oldUser.facebookId, done
        addTwitter = (done) -> addSocial 'twitter', oldUser.twitterId, done
        addGitHub = (done) -> addSocial 'github', oldUser.git_hubId, done

        tasks = [
          saveUser
        ]
        if oldUser.approved
          tasks.push makeFriend
          tasks.push makeMember
        else if oldUser.data.rejected
          tasks.push rejectMember
        else
          tasks.push requestFriend
        if oldUser.admin
          tasks.push makeAdmin
        if oldUser.facebookId
          tasks.push addFacebook
        if oldUser.twitterId
          tasks.push addTwitter
        if oldUser.git_hubId
          tasks.push addGitHub

        async.series tasks, next

      async.auto
        clearSettings: (done) ->
          models.Setting.clear done
        settings: ['clearSettings', (done) ->
          settings = require './vanilla-settings.json'
          models.Setting.create settings, done
        ]
        oldUsers: (done) ->
          q "SELECT * FROM Users ORDER BY id;", done
        friend: (done) ->
          models.Role.get friendRoleId, (err, role) ->
            role.name = 'Friend'
            role.setMeta requirements: [
              {
                id: "1"
                type: "approval"
                roleId: trusteeRoleId
                count: 1
              }
            ]
            role.save done
        trustee: (done) ->
          models.Role.get trusteeRoleId, (err, role) ->
            role.name = 'Trustee'
            role.setMeta requirements: [
              {
                id: "role-1"
                type: 'role'
                roleId: memberRoleId
              }
              {
                id: "text-1"
                type: 'text'
                text: "voted in by the membership"
                roleId: trusteeRoleId
              }
              {
                id: "1"
                type: 'approval'
                roleId: trusteeRoleId
                count: 3
              }
            ]
            role.save done
        supporter: (done) ->
          role = new models.Role
            name: "Supporter"
          role.id = supporterRoleId
          role.setMeta requirements: [
            {
              id: "role-1"
              type: 'role'
              roleId: friendRoleId
            }
            {
              id: "text-1"
              type: 'text'
              text: 'A payment has been made'
            }
            {
              id: "1"
              type: 'approval'
              roleId: trusteeRoleId
              count: 1
            }
          ]
          role.save done
        member: (done) ->
          role = new models.Role
            name: "Member"
          role.id = memberRoleId
          role.setMeta requirements: [
            {
              id: "role-1"
              type: 'role'
              roleId: friendRoleId
            }
            {
              id: "role-2"
              type: 'role'
              roleId: supporterRoleId
            }
            {
              id: "1"
              type: 'approval'
              roleId: trusteeRoleId
              count: 3
            }
            {
              id: "text-1"
              type: 'text'
              text: "Legal name proved to a trustee"
            }
            {
              id: "text-2"
              type: 'text'
              text: "Home address proved to a trustee"
            }
          ]
          role.save done
        roles: ['friend', 'trustee', 'supporter', 'member', (done) -> done()]
        newUsers: ['oldUsers', 'roles', (done, {oldUsers}) ->
          async.mapSeries oldUsers, addUser, done
        ]
      , (err, results) ->
        if err
          console.error err.stack
        process.exit 0
        global.results = results
        global.db = db
        global.orm = orm
        global[k] ?= v for k, v of results
        require('coffee-script/lib/coffee-script/repl').start
          prompt: "REPL> "
          useGlobal: true
