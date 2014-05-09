So Make It Members Area
=======================

This is So Make It's [Members Area][] instance, it installs (as Node
dependencies) the members-area software itself along with a selection
of plugins that we use at [So Make It][].

WARNING: bleeding edge!
-----------------------

Since @Benjie wrote the members area and is a trustee at So Make It we
run the bleeding edge version of the members-area and some of it's
plugins - you should seriously consider using the released npm versions
instead.

Get up and running with Heroku
------------------------------

You can use this repository as a template/quickstart for the members
area to try it out (though probably better to set up your own version
before you go live).

To set up on Heroku, for free, in <5 minutes (assumes you have the
[heroku toolbelt](https://toolbelt.heroku.com/) and git installed):

- Pick a subdomain for your app; replace all occurrences of `APPNAME`
  below with your chosen subdomain.
- `git clone https://github.com/somakeit/somakeit-members-area.git`
- `heroku apps:create APPNAME`
- `heroku addons:add heroku-postgresql`
- `heroku config:set SERVER_ADDRESS="https://APPNAME.herokuapp.com"`
- `heroku config:set SECRET="$(openssl rand -base64 32)"` < pick your
  own random string if you don't have openssl
- `git push heroku master` (this step will take a while)
- `heroku run members migrate` (safe to run at any point in future too)
- `heroku run members seed` (also safe to run at any point in future)
- `heroku restart`
- `heroku addons:add mailgun` - **optional, but highly recommended**
  (won't cost unless you upgrade, but still requires you to enter your
credit card)
- `heroku open` - opens your new members area
- Click "register", register, and then continue to Core Settings and
  press Save.
- Send Benjie some chocolate to thank him for his incredibly dedicated
  hard work ;)

Done! (These instructions are untested, let me know if I skipped a
step!)

[Members Area]: https://github.com/members-area/members-area
[So Make It]: https://www.somakeit.org.uk/
