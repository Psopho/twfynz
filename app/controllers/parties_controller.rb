class PartiesController < ApplicationController

  caches_action :index, :show_party, :third_reading_and_negatived_votes

  layout "parties_layout"

  def index
    @parties = Party.all_size_ordered
    @title = "Parties in Aotearoa New Zealand's Parliament"
    @total_mps = @parties.inject(0) {|count, p| count + p.mps.size }
    @third_reading_matrix = Vote.third_reading_matrix
    # @ayes_third_reading_matrix = Vote.third_reading_matrix :ayes
    # @noes_third_reading_matrix = Vote.third_reading_matrix :noes
  end

  def compare_parties
    @party = Party::get_party params[:name]
    @other_party = Party::get_party params[:other_name]
    @aye_votes_together = @party.aye_votes_together(@other_party)
    @noe_votes_together = @party.noe_votes_together(@other_party)
  end

  def show_party
    party = Party::get_party params[:name]

    if party
      @name = party.name
      @bills_in_charge_of = party.bills_in_charge_of

      @total_party_votes_size = 0 # PartyVote.all_unique.size
      @party_votes_size = 0 # party.party_votes.size
      @party_vote_percent = 0 # @party_votes_size * 100.0 / @total_party_votes_size

      @total_bill_votes_size = 0 # Vote.third_reading_and_negatived_votes.size
      @bill_votes_size = 0 # party.bill_third_reading_and_negatived_votes.size
      @bill_vote_percent = 0 # @bill_votes_size * 100.0 / @total_bill_votes_size

      @party = party
    else
      render(:template => 'parties/invalid_party', :status => 404)
    end
  end

  def contribution_match
    @recent_contribution = Contribution.find(params[:id])
    render :partial => 'recent_contribution', :locals => {:expand => params[:expand]}
  end

  def third_reading_and_negatived_votes
    respond_to do |format|
      header = %Q|"#{Vote.third_reading_and_negatived_votes.collect(&:bill_name).join('","')}"|
      format.csv { render :text => header + "\n" + Vote.vote_vectors.collect(&:to_s).join("\n") }
    end
  end
end
