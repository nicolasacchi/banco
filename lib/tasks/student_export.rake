namespace :banco do
  namespace :student do
    # The student's data as one zip, from the host console (D-360; GDPR art. 15 and 20): the same file as «Scarica i miei dati» on /privacy
    # and the teacher's GET /teacher/students/:key/data. Without OUT it is a dry run: it lists the files and their row counts and writes
    # nothing. With OUT=/path/file.zip (or a directory: the file is named banco-dati-<key>-<date>.zip in it) it writes the zip and records
    # the app event `data_export` (by console, with the operating-system user). It never overwrites a file.
    #
    #   bin/rails banco:student:export [STUDENT=student] [OUT=/path/banco-dati.zip]
    desc "Export a student's data as a zip: [STUDENT=key] [OUT=path]; without OUT lists the counts"
    task export: :environment do
      key = ENV["STUDENT"].presence || Student::OFFICIAL_KEY
      student = Student.find_by(key: key, kind: "student") or abort "no student #{key.first(40).inspect}"
      export = Privacy::StudentExport.new(student)
      out = ENV["OUT"].presence

      if out.nil?
        puts "dry run, student #{student.key}: nothing is written (add OUT=/path/file.zip)"
        export.counts.each { |table, count| puts format("  %-28s %d", table, count) }
        puts "  #{'total'.ljust(28)} #{export.counts.values.sum}"
        next
      end

      path = File.directory?(out) ? File.join(out, export.filename) : out
      abort "#{path} exists: choose another OUT" if File.exist?(path)
      File.binwrite(path, export.zip)
      Privacy::StudentExport.record!(student, by: "console", login: Etc.getpwuid(Process.euid)&.name.to_s)
      puts "wrote #{path} (#{File.size(path)} bytes, #{export.counts.values.sum} rows, student #{student.key})"
    end
  end
end
