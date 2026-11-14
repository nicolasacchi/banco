---
# Gallery of the `code` block (D-329): a whole program in a monospaced box, with its copy button, what S types and what the screen shows.
# Drawn in CI with Chrome at 390, 1280 and dark (test/validation/code_gallery_test.rb), with no finding at all: the page never gets wider than
# the window, and a long line scrolls inside its box. Invented content only. Not a lesson to teach: its cards only show the block.
#
# Shown: the program alone (card 1); with a title, the typed lines, the screen and a note (card 2); a line of 90 characters that scrolls, deep
# indentation and empty lines kept (card 3); between two paragraphs (card 4).
schema: banco.lesson/2
key: ripasso.computer_science.gallery-code
kind: ripasso
subject: computer_science
title_it: "Galleria del blocco programma"
goals_it:
  - "**Copiare** un programma"
  - "**Provare** un programma sul Mac"
skills: [computer_science.gallery]
refs:
  - {source: seconda-2025-26, line: 1, fragment: "programmazione", role: taught_in}
scope: studied
minutes: 10
calculator: false
why_it: "Mostra il blocco che contiene un programma intero da copiare e provare."
---

## Un programma che saluta {idea icon=workflow id=saluta}

::: code
lang: vb
text: |
  Module Program
      Sub Main()
          Console.WriteLine("Ciao, mondo!")
      End Sub
  End Module
:::

## Un programma che chiede un numero {idea icon=box id=chiede}

::: code
lang: vb
title_it: "La torre controlla la quota"
text: |
  Imports System

  Module Program
      Sub Main()
          Console.Write("Quota in piedi: ")
          Dim quota As Integer = CInt(Console.ReadLine())
          If quota < 0 Or quota > 45000 Then
              Console.WriteLine("Quota non valida.")
          Else
              Console.WriteLine("Quota: " & quota & " piedi")
          End If
      End Sub
  End Module
input_it:
  - "35000"
output: |
  Quota in piedi: 35000
  Quota: 35000 piedi
note_it: "Scrivi 35000 e premi Invio."
:::

## Righe lunghe e rientri {idea icon=repeat id=lunghe}

::: code
lang: vb
title_it: "Una riga di 90 caratteri"
text: |
  Module Program
      Sub Main()
          For i As Integer = 1 To 3
              If i = 2 Then
                  Console.WriteLine("Giro due: questa riga è molto lunga e non va a capo..")

              End If
          Next
      End Sub
  End Module
output: |
  Giro due: questa riga è molto lunga e non va a capo..
:::

## Un programma dopo il testo {idea icon=diamond id=dopo-testo}

Copia il programma qui sotto in `Program.vb`.

::: code
lang: vb
text: |
  Module Program
      Sub Main()
          Dim nome As String = Console.ReadLine()
          Console.WriteLine("Ciao, " & nome & "!")
      End Sub
  End Module
input_it:
  - "Marta"
output: |
  Marta
  Ciao, Marta!
:::

Poi scrivi `dotnet run`.
