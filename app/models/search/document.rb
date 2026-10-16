module Search
  # A row of the index (search_documents): a read model for tests and the status task. Written only by Search::Index.
  class Document < Record
    self.table_name = "search_documents"
    self.inheritance_column = nil
  end
end
