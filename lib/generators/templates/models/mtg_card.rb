class MtgCard < ActiveRecord::Base
  require 'mtg_helpers'
  include MtgHelpers

  has_many :mtg_card_types
  has_many :mtg_types, :through => :mtg_card_types
  belongs_to :mtg_set

  validates :name, :presence => true
  validates :mtg_set_id,  :presence => true

  alias_method :types, :mtg_types
  alias_method :set, :mtg_set

  def transformed_side
    if transformed_id.present?
      MtgCard.find_by_multiverse_id(transformed_id)
    end
  end

  # This is the default location for your version of Rails. You can configure
  # this however you want, but be sure you move the images first.
  def image_url
    "/assets/#{set.folder_name}/#{multiverse_id}.jpg"
  end

  def set_symbol_url
    "/assets/#{set.folder_name}/#{slugify(rarity)}_icon.jpg"
  end

end

