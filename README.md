celluloid-smtp-sample
=====================

Clone this repo and install the dependencies with bundler.

Then choose to run a celluloid or EM based server by running `./bin/celluloid` or `/bin/em`.

You can use (swaks)[http://www.jetmore.org/john/code/swaks/] to send mails into the server and see how it behaves, something like this:

```
$ swaks -s 127.0.0.1 -p 1025 -t joe@mailinator.com
```

Have fun :)
