# The libraries a free page may declare (config/banco/pages_libs.yml, vendored under vendor/pages/, SPEC B2, C1).
# A page names "three@0.186.1" or an addon "three-addons@0.186.1:controls/OrbitControls.js". Files are served by lookup
# in a listing of the vendored directory, never by joining a path from the request.
module Pages
  module Libs
    ROOT = Rails.root.join("vendor/pages")
    ADDON = /\A(?<name>[a-z][a-z0-9-]*)-addons@(?<version>\d+\.\d+\.\d+):(?<path>[A-Za-z0-9_.\/-]+)\z/
    PLAIN = /\A(?<name>[a-z][a-z0-9-]*)@(?<version>\d+\.\d+\.\d+)\z/
    SEGMENT = %r{\A[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*\z}

    module_function

    def config = @config ||= YAML.safe_load_file(Rails.root.join("config/banco/pages_libs.yml")).fetch("libs")

    # {name:, version:, addon: path-or-nil} of a declared lib, or nil when the string is not one the server vendors.
    def parse(spec)
      if (m = ADDON.match(spec.to_s))
        lib = config[m[:name]]
        return nil unless lib && lib["version"] == m[:version] && lib["scope"] == "page" && Array(lib["addons"]).include?(m[:path])

        { name: m[:name], version: m[:version], addon: m[:path] }
      elsif (m = PLAIN.match(spec.to_s))
        lib = config[m[:name]]
        return nil unless lib && lib["version"] == m[:version] && lib["scope"] == "page"

        { name: m[:name], version: m[:version], addon: nil }
      end
    end

    def dir_name(name, version) = "#{name}@#{version}"

    # The files of a vendored directory (relative), sorted; [] when the name and version are not vendored.
    def files(name, version)
      lib = config[name.to_s]
      return [] unless lib && lib["version"] == version.to_s

      dir = ROOT.join(dir_name(name, version))
      return [] unless File.directory?(dir)

      Dir.glob("**/*", base: dir.to_s).select { |f| File.file?(dir.join(f)) && f != "SHA256SUMS" }.sort
    end

    def read(name, version, path)
      return nil unless path.to_s.match?(SEGMENT) && files(name, version).include?(path)

      File.binread(ROOT.join(dir_name(name, version), path))
    end

    # The import map entries for a manifest's libs: {"three" => "/vendor/three@0.186.1/three.module.js", ...}.
    def importmap(specs)
      specs.each_with_object({}) do |spec, map|
        parsed = parse(spec) or next
        lib = config.fetch(parsed[:name])
        base = "/vendor/#{dir_name(parsed[:name], parsed[:version])}"
        if parsed[:addon]
          map["#{parsed[:name]}/addons/#{parsed[:addon]}"] = "#{base}/addons/#{parsed[:addon]}"
        else
          lib.fetch("imports", {}).each { |id, file| map[id] = "#{base}/#{file}" }
        end
      end
    end

    # Every specifier any page library could be imported by (declared or not): to tell "not declared" from "unknown".
    def all_specifiers
      specs = config.select { |_, l| l["scope"] == "page" }.flat_map do |name, l|
        l.fetch("imports", {}).keys + Array(l["addons"]).map { |a| "#{name}/addons/#{a}" }
      end
      specs
    end

    # The bare specifiers a page may import for these libs.
    def specifiers(specs) = importmap(specs).keys

    # Bytes the browser transfers for these libs, gzipped as the edge would (the card's "circa N KB").
    def transfer_bytes(specs)
      urls = importmap(specs).values
      # three.module.js imports three.core.js: count every file of the library directory that the map reaches
      extra = specs.filter_map { |s| parse(s) }.reject { |p| p[:addon] }.flat_map { |p| files(p[:name], p[:version]).reject { |f| f.start_with?("addons/") || f == "LICENSE" }.map { |f| "/vendor/#{dir_name(p[:name], p[:version])}/#{f}" } }
      (urls | extra).sum do |url|
        _, _, rest = url.partition("/vendor/")
        dir, _, file = rest.partition("/")
        name, version = dir.split("@", 2)
        bytes = read(name, version, file) or next 0
        Zlib.gzip(bytes).bytesize
      end
    end
  end
end
