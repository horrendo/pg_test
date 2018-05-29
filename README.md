# pg_test - A postgres DB Unit Test driver

We have adopted the use of [pgTAP](https://pgtap.org/) as our postgres database testing framework. It provides an extremely comprehensive suite of assertion functions but the associated command line test runner (pg_prove) is based on Perl and requires a bit of setup to run.

I decided to write a substitute based on [Crystal](https://crystal-lang.org/) because it can be compiled into a single standalone executable. Plus I was looking for something to push me into learning the language. :smiley:

## Running locally

If you have crystal (and the postgresql client library) installed locally, you can simply run the tool as follows:

```bash
[~/git/pg_test]$ crystal pg_test.cr -- -d bcaas -U bcaas_owner *sql
W|07:05:39.303|crystal-run-pg_test.tmp|00.000756|00.000756|Starting
W|07:05:39.309|crystal-run-pg_test.tmp|00.007008|00.006252|Processing dbobj.sql (1/1)
W|07:05:39.742|crystal-run-pg_test.tmp|00.439895|00.432887|dbobj.sql: 354/354 ok
W|07:05:39.742|crystal-run-pg_test.tmp|00.440208|00.000313|Program completed
```

If you are running on a Mac you *may* see output like this:

```bash
[~/git/pg_test]$ crystal pg_test.cr -- -d bcaas -U bcaas_owner *sql
Package libssl was not found in the pkg-config search path.
Perhaps you should add the directory containing `libssl.pc'
to the PKG_CONFIG_PATH environment variable
No package 'libssl' found
Package libcrypto was not found in the pkg-config search path.
Perhaps you should add the directory containing `libcrypto.pc'
to the PKG_CONFIG_PATH environment variable
No package 'libcrypto' found
:
```

In this case, just find out where either of these `.pc` files are and set the environment variable accordingly:

```bash
[~/git/pg_test]$ find / -name libssl.pc 2>/dev/null
/usr/local/Cellar/openssl@1.1/1.1.0g_1/lib/pkgconfig/libssl.pc
/usr/local/Cellar/openssl@1.1/1.1.0h/lib/pkgconfig/libssl.pc
/usr/local/Cellar/openssl@1.1/1.1.0f/lib/pkgconfig/libssl.pc
/usr/local/Cellar/openssl/1.0.2o_1/lib/pkgconfig/libssl.pc
/usr/local/Cellar/openssl/1.0.2n/lib/pkgconfig/libssl.pc
/usr/local/Cellar/openssl/1.0.2k/lib/pkgconfig/libssl.pc
/usr/local/Cellar/openssl/1.0.2l/lib/pkgconfig/libssl.pc
/usr/local/Cellar/openssl/1.0.2j/lib/pkgconfig/libssl.pc
:
[~/git/pg_test]$ export PKG_CONFIG_PATH=/usr/local/Cellar/openssl@1.1/1.1.0h/lib/pkgconfig
[~/git/pg_test]$ crystal pg_test.cr -- -d bcaas -U bcaas_owner *sql
W|07:05:39.303|crystal-run-pg_test.tmp|00.000756|00.000756|Starting
W|07:05:39.309|crystal-run-pg_test.tmp|00.007008|00.006252|Processing dbobj.sql (1/1)
W|07:05:39.742|crystal-run-pg_test.tmp|00.439895|00.432887|dbobj.sql: 354/354 ok
W|07:05:39.742|crystal-run-pg_test.tmp|00.440208|00.000313|Program completed
```

### Building a standalone executable
Since you'll probably be running this more than once, you can save yourself a few seconds by building a standalone executable:

```bash
[~/git/pg_test]$ crystal build pg_test.cr
[~/git/pg_test]$ cp pg_test /usr/local/bin
[~/git/pg_test]$ which pg_test
/usr/local/bin/pg_test
[~/git/pg_test]$ pg_test --help
W|07:13:19.156|pg_test|00.000853|00.000853|Starting
Usage: pg_test [options] test_script_file(s)
    -D dir, --Directory=dir          Read script files from {dir}
    -d name, --dbname=name           database name to connect to
    -U name, --username=name         database user name
    -h name, --host=name             database server host
    -v, --verbose                    Increase the logging verbosity
    -h, --help                       Show this help
[~/git/pg_test]$ pg_test -d bcaas -U bcaas_owner *sql
W|07:13:36.405|pg_test|00.000663|00.000663|Starting
W|07:13:36.411|pg_test|00.006528|00.005865|Processing dbobj.sql (1/1)
W|07:13:36.758|pg_test|00.353255|00.346727|dbobj.sql: 354/354 ok
W|07:13:36.758|pg_test|00.353668|00.000413|Program completed
```
## Building a Docker image
To make life a little easier with ci/cd this repo includes a Dockerfile that builds a standalone version of pg_test into a small linux image. The image has been pushed to Docker Hub as `horrendo/pg_test`.

### Running the Docker image
This example presumes I have pulled the above image from Docker Hub:

```bash
[~/git/bcaas/database/t]$ docker run -it --rm --add-host=db:192.168.101.144 -v `pwd`:/tmp horrendo/pg_test sh -c 'pg_test -h db -d bcaas -U bcaas_owner -D /tmp'
W|00:06:31.161|pg_test|00.000037|00.000037|Starting
W|00:06:31.182|pg_test|00.020880|00.020843|Processing /tmp/dbobj.sql (1/1)
W|00:06:31.583|pg_test|00.422007|00.401127|/tmp/dbobj.sql: 354/354 ok
W|00:06:31.584|pg_test|00.422865|00.000858|Program completed
```

## Environment Variables
You don't have to specify the database name and username on the command line. The tool respects the following standard [Postgres environment variables](https://www.postgresql.org/docs/current/static/libpq-envars.html):

* `PGDATABASE`
* `PGUSER`
* `PGPASSWORD` (not a command line arg)
* `PGPORT` (not a command line arg)

```bash
[~/git/pg_test]$ export PGDATABASE=bcaas
[~/git/pg_test]$ export PGUSER=bcaas_owner
[~/git/pg_test]$ pg_test *sql
W|07:14:26.036|pg_test|00.000552|00.000552|Starting
W|07:14:26.043|pg_test|00.006710|00.006158|Processing dbobj.sql (1/1)
W|07:14:26.412|pg_test|00.376283|00.369573|dbobj.sql: 354/354 ok
W|07:14:26.413|pg_test|00.376584|00.000301|Program completed
```

## Errors
During script execution, any test failures are output showing the test and the line number in the file. For example:

```bash
[~/git/pg_test]$ cat -n t1.sql
     1	select plan(3);
     2	
     3	select has_table('client');
     4	select has_table('doofus');
     5	select has_table('buyer');
[~/git/pg_test]$ pg_test t1.sql
W|10:21:58.531|pg_test|00.000551|00.000551|Starting
W|10:21:58.535|pg_test|00.004597|00.004046|Processing t1.sql (1/1)
W|10:21:58.560|pg_test|00.028938|00.024341|Failed test 2/3 (#4): Table doofus should exist
W|10:21:58.563|pg_test|00.032119|00.003181|t1.sql: Looks like you failed 1 test of 3
W|10:21:58.563|pg_test|00.032355|00.000236|Program completed
```

This shows there was an error with the test found at line 4 `(#4)` in t1.sql.pg_test