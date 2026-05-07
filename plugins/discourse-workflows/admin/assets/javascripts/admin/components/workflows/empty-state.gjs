import DButton from "discourse/components/d-button";
import emoji from "discourse/helpers/emoji";

<template>
  <div class="workflows-empty-state">
    {{#if @emoji}}
      <span class="workflows-empty-state__icon">{{emoji @emoji}}</span>
    {{/if}}
    <h2 class="workflows-empty-state__title">{{@title}}</h2>
    <p class="workflows-empty-state__description">{{@description}}</p>
    {{#if @onAction}}
      <DButton
        @action={{@onAction}}
        @label={{@buttonLabel}}
        @translatedLabel={{@translatedButtonLabel}}
        @icon={{@buttonIcon}}
        class="btn-primary"
      />
    {{/if}}
  </div>
</template>
