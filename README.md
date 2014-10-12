# RubySoul

## What is it ?

__RubySoul__ is a NetSoul client who give you a console shell in order to use functionalities like chat, status and others. It is writing in pure ruby. This NetSoul client is written in pure ruby and use now both authentication mode, Kerberos and MD5.

## How does it work

### Kerberos authentication
Ruby have no kerberos bindind. I wrote a ruby/c extension who use C libgssapi and C libkrb5 to solve this problem. 
From the rubysoul directory go to the lib/kerberos :

    cd ./lib/kerberos


Build the NsToken ruby/c extension :

    ruby extconf.rb
    make
    cd ../..


Now edit your conf/config.yml file and put your login and unix password :

    #--- | Application config
    :login: 'login_l'
    :socks_password: ''
    :unix_password: 'my_unix_password'
    :state: 'actif'		#--- | Could be, actif, away, idle, lock
    :location: '@ Home'
    :user_group: etna_2008
    :system: Unix
    ...


Run the rubysoul.rb script :

    ruby rubysoul.rb


### MD5 authentication
You need only to edit conf/config.yml file and put your login and socks password :

    #--- | Application config
    :login: 'login_l'
    :socks_password: 'my_socks_password'
    :unix_password: ''
    :state: 'actif'		#--- | Could be, actif, away, idle, lock
    :location: '@ Home'
    :user_group: etna_2008
    :system: Unix
    ...


### Run RubySoul

You can run the script on terminal :

    ruby rubysoul.rb
    rubysoul#> ?
