namespace :banco do
  namespace :syllabus do
    # FILE=path reads a file; FILE=- reads standard input (how the operator
    # imports in production: docker compose exec -T banco ... FILE=- < file).
    read_input = lambda do
      file = ENV["FILE"].presence or abort "FILE=path|- is required"
      ENV["SOURCE"].presence or abort "SOURCE=key is required"
      file == "-" ? $stdin.binmode.read : File.binread(file)
    end

    desc "Import a programme file line by line: SOURCE=key FILE=path|-"
    task import: :environment do
      text = read_input.call
      Syllabus::Importer.import(ENV.fetch("SOURCE"), text)
      puts "imported #{ENV.fetch('SOURCE')} #{Syllabus::Importer.stats(text)}"
    rescue Syllabus::Error => e
      abort "import failed: #{e.message}"
    end

    desc "Verify the imported lines against the file: SOURCE=key FILE=path|-"
    task verify: :environment do
      text = read_input.call
      puts "#{Syllabus::Importer.verify(ENV.fetch('SOURCE'), text)} ok"
    rescue Syllabus::Error => e
      abort "verify failed: #{e.message}"
    end
  end
end
