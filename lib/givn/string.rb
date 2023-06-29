class String
  def no_to_en_f
    self.to_s.gsub(",", "").to_f
  end
end
