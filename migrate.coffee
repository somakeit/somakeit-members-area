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
          newUser.verified = oldUser.approved
          newUser.save (err) ->
            return done err if err
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
          role.setMeta
            requirements: [
              {
                id: "role-1"
                type: 'role'
                roleId: friendRoleId
              }
              {
                id: "text-1"
                type: 'text'
                text: 'A payment has been made'
                roleId: trusteeRoleId
              }
              {
                id: "1"
                type: 'approval'
                roleId: trusteeRoleId
                count: 1
              }
            ]
            subscriptionRequired: true
          role.save done
        member: (done) ->
          role = new models.Role
            name: "Member"
          role.id = memberRoleId
          role.setMeta
            requirements: [
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
                roleId: trusteeRoleId
              }
              {
                id: "text-2"
                type: 'text'
                text: "Home address proved to a trustee"
                roleId: trusteeRoleId
              }
            ]
            subscriptionRequired: true
          role.save done
        roles: ['friend', 'trustee', 'supporter', 'member', (done) -> done()]
        newUsers: ['oldUsers', 'roles', (done, {oldUsers}) ->
          async.mapSeries oldUsers, addUser, done
        ]
        oldPayments: (done) ->
          q "SELECT * FROM Payments ORDER BY id;", done
        newPayments: ['newUsers', 'oldPayments', (done, results) ->
          newPayments = []
          for payment in results.oldPayments
            try
              payment.data = JSON.parse payment.data
            catch
              payment.data = {}
            made = new Date Date.parse payment.made
            from = new Date Date.parse payment.subscriptionFrom
            end = new Date Date.parse payment.subscriptionUntil
            meta =
              legacy: payment.data
            if payment.type is 'GC'
              meta.gocardlessBillId = payment.data.original.data.gocardlessBill.id
            newPayment =
              user_id: payment.UserId
              transaction_id: null
              type: payment.type
              amount: payment.amount
              status: payment.data.status ? "paid"
              include: true
              when: made
              period_from: from
              period_count: Math.round(((+end - +from)/(24*60*60*1000)) / 30) # Rough number of months
              meta: meta
            newPayments.push newPayment
          models.Payment.create newPayments, done
        ]
        heal: ['newPayments', (done, results) ->
          # Heh heh heh, sorry Chris
          # Heh heh heh, sorry everyone who paid by STO/BGC
          nonBankingPaymentTypes = ['GC', 'CASH', 'PAYPAL', 'OTHER']
          models.Payment.find()
            .where(status: ['failed', 'cancelled'], include: true)
            .where("(status IN ('failed', 'cancelled')) OR (type NOT IN ?)", [nonBankingPaymentTypes])
            .order("-period_from")
            .all (err, payments) ->
              return done err if err
              uninclude = (payment, next) ->
                payment.include = false
                if payment.type in nonBankingPaymentTypes
                  action = 'save'
                else
                  action = 'remove'
                payment[action] (err) ->
                  return next err if err
                  payment.getUser (err, user) ->
                    return next err if err
                    paidUntil = new Date +user.paidUntil
                    paidUntil.setMonth(paidUntil.getMonth()-payment.period_count)
                    user.paidUntil = paidUntil
                    user.save (err) ->
                      return next err if err
                      midnight = new Date +payment.period_from
                      midnight.setHours(0)
                      midnight.setMinutes(0)
                      midnight.setSeconds(0)
                      models.Payment.find()
                        .where("id <> ? AND user_id = ? AND period_from >= ?", [payment.id, user.id, midnight])
                        .order("period_from")
                        .all (err, paymentsToRewrite) ->
                          rewrite = (p, done) ->
                            from = new Date +p.period_from
                            from.setMonth(from.getMonth() - payment.period_count)
                            p.period_from = from
                            p.save done
                          async.eachSeries paymentsToRewrite, rewrite, ->
                            if payment.type in nonBankingPaymentTypes
                              console.log "Decreased #{user.fullname}'s paid until by #{payment.period_count} month(s) because of failed payment on #{payment.when}"
                            else
                              console.log "Decreased #{user.fullname}'s paid until by #{payment.period_count} month(s) because of removed bank payment"
                            next null, payment
              async.mapSeries payments, uninclude, done
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
