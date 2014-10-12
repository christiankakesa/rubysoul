# RubySoul Server

## What is it ?

Is a NetSoul client just for authentification to IONIS network area.

This NetSoul client is written in ruby and the version 0.7.04 use both authentication mode Kerberos and MD5. Works with ruby 1.9. Now implement pure ruby REACTOR design pattern.


## How does it work

### Kerberos authentication

Ruby have no kerberos bindind. I wrote a ruby/c extension who use C libgssapi and C libkrb5 to solve this problem. 
From the rubysoul-server directory go to the lib/kerberos :

    cd ./lib/kerberos
 

Build the NsToken ruby/c extension :

    ruby extconf.rb
    make
    cd ../..


Now edit your config.yml file and put your login and unix password :

    #--- | Application config
    :login: kakesa_c
    :socks_password: '' #--- | Not needed in kerberos authentication
    :unix_password: 'your_unix_password' #--- | Only if you have build lib/kerberos/NsToken, if you don't must be empty.
    ...


### MD5 authentication

You need only to edit config.yml file and put your login and socks password :

    #--- | Application config
    :login: kakesa_c
    :socks_password: 'my_socks_password'
    ...


### Run rubySoul Server

You can run the script on terminal or in you ~/.xsession file :

    ruby rubysoul-server.rb


