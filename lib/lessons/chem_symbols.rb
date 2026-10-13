# frozen_string_literal: true

module Lessons
  # The element symbols a chemistry formula may use (E-CHEM-SYMBOL, D-282): every symbol inside \ce{...} or \mathrm{...} of a lesson formula
  # is an element symbol, case-exact. The list is the table chem/elements once T7 has written it (Lessons::VettedData); until then the 118
  # symbols of the IUPAC periodic table below. Pure: no database. (Lessons::Chem, T7's, parses formulas into atoms; this only reads the
  # symbols of a formula as a lesson writes it in TeX.)
  module ChemSymbols
    FALLBACK = %w[H He Li Be B C N O F Ne Na Mg Al Si P S Cl Ar K Ca Sc Ti V Cr Mn Fe Co Ni Cu Zn Ga Ge As Se Br Kr Rb Sr Y Zr Nb Mo Tc Ru Rh
                  Pd Ag Cd In Sn Sb Te I Xe Cs Ba La Ce Pr Nd Pm Sm Eu Gd Tb Dy Ho Er Tm Yb Lu Hf Ta W Re Os Ir Pt Au Hg Tl Pb Bi Po At Rn Fr Ra
                  Ac Th Pa U Np Pu Am Cm Bk Cf Es Fm Md No Lr Rf Db Sg Bh Hs Mt Ds Rg Cn Nh Fl Mc Lv Ts Og].freeze
    # Unit symbols that look like an element's and are not one: \mathrm{kJ}, \mathrm{Hz}, \mathrm{L} are not misspelled elements.
    UNITS = %w[A J L M W T Hz Bq Gy Wb Sv].freeze
    TOKEN = /[A-Z][a-z]*/

    module_function

    def symbols
      @symbols ||= VettedData.table("chem/elements")&.dig("elements")&.map { |e| e["symbol"] } || FALLBACK
    end

    def known?(symbol) = symbols.include?(symbol)

    # The contents of every \name{...} in +tex+ (brace-balanced, nested ones included in their parent): [text].
    def arguments(tex, name)
      out = []
      tex.scan(/\\#{name}(?![A-Za-z])\s*\{/) do
        start = Regexp.last_match.end(0)
        depth = 1
        i = start
        while i < tex.length && depth.positive?
          depth += 1 if tex[i] == "{"
          depth -= 1 if tex[i] == "}"
          i += 1
        end
        out << tex[start...(i - 1)] if depth.zero?
      end
      out
    end

    # The tokens of a \ce argument that are not element symbols: the words of \text{...}, the macros (\Delta, \bond) and the lowercase
    # state marks ((aq), (s), (l), (g)) are not symbols; what is left is read as capital letter plus lowercase letters.
    def unknown_in_ce(argument)
      bare = argument.gsub(/\\(?:text|textit|mathrm|mathit)\s*\{[^{}]*\}/, " ").gsub(/\\[A-Za-z]+/, " ")
      bare.scan(TOKEN).reject { |t| known?(t) }.uniq
    end

    def unknown_in_mathrm(argument)
      bare = argument.gsub(/\\[A-Za-z]+/, " ")
      bare.scan(TOKEN).reject { |t| known?(t) || UNITS.include?(t) }.uniq
    end

    # Every symbol of +tex+ that is not an element: inside \ce{...} and \mathrm{...} (\pu{...} holds numbers and units, not symbols).
    def unknown(tex)
      (arguments(tex, "ce").flat_map { |a| unknown_in_ce(a) } + arguments(tex, "mathrm").flat_map { |a| unknown_in_mathrm(a) }).uniq
    end

    # Whether +tex+ uses mhchem's commands.
    def mhchem?(tex) = tex.match?(/\\(?:ce|pu)(?![A-Za-z])/)
  end
end
