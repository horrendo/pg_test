require "option_parser"
require "logger"
require "db"
require "pg"

module PG_TEST

  class Runner
    getter log = Logger.new(STDOUT)

    def initialize
      t_start = Time.now
      t_prev = t_start
      progname = File.basename(PROGRAM_NAME)
      log.level = Logger::WARN
      log.formatter = Logger::Formatter.new do |severity, datetime, _, message, io|
        total_time = datetime - t_start
        delta_time = datetime - t_prev
        t_prev = datetime
        io.printf("%s|%s|%s|%09.6f|%09.6f|%s", severity.to_s[0], datetime.to_s("%H:%M:%S.%L"), progname, total_time.total_seconds, delta_time.total_seconds, message)
      end
    end

    def main
      sql_files = [] of String
      sql_statements = {} of String => Array(String)
      sql_stmt_lno = {} of String => Array(Int32)

      log.warn("Starting")

      OptionParser.parse! do |parser|
        parser.banner = "Usage: pg_test [options] test_script_file(s)"
        parser.on("-D dir", "--Directory=dir", "Read script files from {dir}") { |dir| sql_files += Dir.glob(File.join(dir, "*.sql")) }
        parser.on("-d name", "--dbname=name", "database name to connect to") { |name| ENV["PGDATABASE"] = name }
        parser.on("-U name", "--username=name", "database user name") { |name| ENV["PGUSER"] = name }
        parser.on("-h name", "--host=name", "database server host") { |name| ENV["PGHOST"] = name }
        parser.on("-v", "--verbose", "Increase the logging verbosity") do
          if log.level != Logger::DEBUG
            log.level = Logger::Severity.values[log.level.value - 1]
            log.log(log.level, "Log level is now #{log.level}")
          end
        end
        parser.on("-h", "--help", "Show this help") { puts parser; exit(0) }
        parser.invalid_option { |arg| puts "Option #{arg} is invalid\n\n#{parser}"; exit(1) }
        parser.unknown_args { |a1, a2| sql_files += a1 + a2 }
      end

      raise "No sql files to process" if sql_files.empty?

      rx_sql = /(?<pre>.*?)^(?<sql>(select|with)\b.+?;\s*?$)/im
      rx_resp_plan = /^\s*1[.][.](\d+)/
      rx_resp_ok = /^\s*ok\s*(\d+)\s*[-]\s*(.*)/i
      rx_resp_fail = /^\s*not ok\s*(\d+)\s*[-]\s*(.*)/i

      sql_files.each do |sql_file|
        if File.exists?(sql_file) && File.readable?(sql_file)
          sql_statements[sql_file] = [] of String
          sql_stmt_lno[sql_file] = [] of Int32
          log.info("Parsing #{sql_file}")

          offset = 0
          line_number = 1
          slurp = File.read(sql_file)
          loop do
            match = rx_sql.match(slurp, offset) || break
            pre = match.named_captures["pre"]
            sql = match.named_captures["sql"]
            line_number += pre.count('\n') if pre
            if sql
              sql_statements[sql_file] << sql
              sql_stmt_lno[sql_file] << line_number
              line_number += sql.count('\n')
            end
            offset = match.end || break
          end
        else
          raise "#{sql_file} does not exist or is not readable"
        end
        if sql_statements[sql_file].empty?
          sql_statements.delete(sql_file)
          sql_stmt_lno.delete(sql_file)
        end
      end

      raise "No sql statements found" if sql_statements.empty?

      log.info("Connecting to DB")
      uri = URI.new
      uri.scheme = "postgres"
      uri.user = ENV["PGUSER"]
      uri.password = ENV["PGPASSWORD"]?
      uri.host = ENV["PGHOST"]?
      uri.port = ENV["PGPORT"]?.try &.to_i
      uri.path = "/" + ENV["PGDATABASE"]

      log.debug("db uri = #{uri}")

      DB.open uri do |db|
        log.info("Connected")
        sql_statements.each_with_index(1) do |pair, file_number|
          file, stmts = pair
          log.warn("Processing #{file} (#{file_number}/#{sql_statements.size})")
          db.exec "begin"
          planned = 0
          n_ok = 0
          n_fail = 0
          problem : String? = nil
          stmts.each_with_index do |stmt, stmt_no|
            lno = sql_stmt_lno[file][stmt_no]
            db.query stmt.rstrip(';') do |rset|
              rset.each do
                response = rset.read(String)
                if planned == 0
                  if rx_resp_plan.match(response)
                    planned = $1
                  end
                elsif rx_resp_ok.match(response)
                  n_test = $1
                  test = $2
                  n_ok += 1
                  log.info("ok #{n_test}/#{planned}: #{test}")
                elsif rx_resp_fail.match(response)
                  n_test = $1
                  test = $2.strip
                  n_fail += 1
                  log.warn("Failed test #{n_test}/#{planned} (##{lno}): #{test}")
                  log.info(stmt)
                end
              end
            end
          end
          db.query "select * from finish()" do |rset|
            rset.each do
              problem = rset.read(String).lstrip(" #")
            end
          end
          db.exec "rollback"
          if !problem
            log.warn("#{file}: #{n_ok}/#{planned} ok")
          else
            log.warn("#{file}: #{problem}")
          end
        end
      end

      error_code = 0
    rescue e
      log.error(e.message)
      error_code = 1
    ensure
      log.warn("Program completed")
      exit(error_code)
    end
  end
end

PG_TEST::Runner.new.main
