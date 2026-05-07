import { concat, hash } from "@ember/helper";
import DTooltip from "discourse/float-kit/components/d-tooltip";
import concatClass from "discourse/helpers/concat-class";
import { number } from "discourse/lib/formatter";

const DStatTile = <template>
  <div class="d-stat-tile" role="group">
    <div class="d-stat-tile__top">
      <span class="d-stat-tile__label">{{@label}}</span>
      {{#if @tooltip}}
        <DTooltip
          class="d-stat-tile__tooltip"
          @icon="circle-question"
          @content={{@tooltip}}
        />
      {{/if}}
    </div>
    {{#if @url}}
      <a href={{@url}} class="d-stat-tile__value" title={{@value}}>
        {{if @formattedValue @formattedValue (number @value)}}
      </a>
    {{else}}
      <span class="d-stat-tile__value" title={{@value}}>
        {{if @formattedValue @formattedValue (number @value)}}
      </span>
    {{/if}}
  </div>
</template>;

const DStatTiles = <template>
  <div
    class={{concatClass "d-stat-tiles" (if @format (concat "--" @format))}}
    ...attributes
  >
    {{yield (hash Tile=DStatTile)}}
  </div>
</template>;

export default DStatTiles;
